import AppKit
import XCTest

@testable import GrammarCorrection

/// Learn mode explanations are kept so they can be reviewed later from Recent Lessons.
final class LessonHistoryTests: XCTestCase {
  private func temporaryFile() -> URL {
    let name = "lessons-\(UUID().uuidString)"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
    let mistakes = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-mistakes.json")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: mistakes)
    }
    return url
  }

  @MainActor
  func testRepeatedChangesAreCountedAcrossLessonsAndSurviveRelaunch() {
    let file = temporaryFile()
    let history = LessonHistory(fileURL: file)

    history.add(["needsed → needed: spelling", "status progress → progress status: adjective first"], at: Date(timeIntervalSince1970: 1))
    history.add(["\"Needsed\" → \"needed\": spelling mistake"], at: Date(timeIntervalSince1970: 2))
    history.add(["needsed → needed: typo", "pls → please: spell out"], at: Date(timeIntervalSince1970: 3))
    history.add(["pls → please: spell it out"], at: Date(timeIntervalSince1970: 4))
    history.add(["pls → please"], at: Date(timeIntervalSince1970: 5))

    let repeated = history.repeatedMistakes()
    XCTAssertEqual(repeated.map(\.line), ["pls → please: spell it out (3 times)", "needsed → needed: typo (3 times)"])
    XCTAssertEqual(LessonHistory(fileURL: file).repeatedMistakes(), repeated, "Counts survive a relaunch")
  }

  @MainActor
  func testClearForgetsRepeatedMistakesToo() {
    let file = temporaryFile()
    let history = LessonHistory(fileURL: file)
    history.add(["teh → the: spelling"])
    history.add(["teh → the: spelling"])
    XCTAssertEqual(history.repeatedMistakes().count, 1)

    history.clear()

    XCTAssertTrue(history.repeatedMistakes().isEmpty)
    XCTAssertTrue(LessonHistory(fileURL: file).repeatedMistakes().isEmpty)
  }

  func testMistakeLinesWithoutAnArrowOrPhraseAreIgnored() {
    XCTAssertNil(RepeatedMistake(line: "Good job overall", at: Date()))
    XCTAssertNil(RepeatedMistake(line: " → after: why", at: Date()))
    XCTAssertEqual(RepeatedMistake(line: "a → b", at: Date())?.reason, nil)
  }

  @MainActor
  func testWindowShowsRepeatedMistakesFirst() {
    let mistake = RepeatedMistake(line: "needsed → needed: spelling", at: Date())
    var repeated = try? XCTUnwrap(mistake)
    repeated?.count = 3
    let text = LessonsWindow.formatted(
      [Lesson(date: Date(), lines: ["pls → please: spell out"])], repeated: repeated.map { [$0] } ?? []
    ).string

    // Learn panel colors put each reason on its own line.
    XCTAssertTrue(text.hasPrefix("Watch Out For\nneedsed → needed\nspelling (3 times)\n"), text)
    XCTAssertTrue(text.contains("pls → please\nspell out"), text)
  }

  @MainActor
  func testLessonsAreNewestFirstCappedAndSurviveRelaunch() {
    let file = temporaryFile()
    let history = LessonHistory(fileURL: file)

    for index in 0..<(LessonHistory.maxLessons + 3) {
      history.add(["a\(index) → b\(index): why"], at: Date(timeIntervalSince1970: TimeInterval(index)))
    }
    history.add([])

    XCTAssertEqual(history.lessons.count, LessonHistory.maxLessons)
    XCTAssertEqual(history.lessons.first?.lines, ["a22 → b22: why"])
    XCTAssertEqual(LessonHistory(fileURL: file).lessons, history.lessons)
  }

  @MainActor
  func testClearRemovesSavedLessons() {
    let file = temporaryFile()
    let history = LessonHistory(fileURL: file)
    history.add(["a → b: why"])

    history.clear()

    XCTAssertTrue(history.lessons.isEmpty)
    XCTAssertTrue(LessonHistory(fileURL: file).lessons.isEmpty)
  }

  @MainActor
  func testWindowTextShowsWhenEachLessonHappened() {
    let now = Date()
    let text = LessonsWindow.formatted([
      Lesson(date: now.addingTimeInterval(-60), lines: ["status progress → a progress status: adjective first"]),
      Lesson(date: now.addingTimeInterval(-7200), lines: ["revert back → get back: natural phrase"]),
    ], now: now).string

    XCTAssertTrue(text.hasPrefix("1 minute ago\nstatus progress → a progress status"), text)
    XCTAssertTrue(text.contains("2 hours ago\nrevert back → get back"), text)
  }

  @MainActor
  func testEmptyWindowExplainsHowToGetLessons() {
    XCTAssertTrue(LessonsWindow.formatted([]).string.contains("Turn on Learn"))
  }

  @MainActor
  func testMenuItemIsEnabledOnceALessonIsSaved() throws {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    try Settings.save(Settings())
    try? FileManager.default.removeItem(at: LessonHistory.defaultFileURL)
    addTeardownBlock {
      try? Settings.save(Settings())
      try? FileManager.default.removeItem(at: LessonHistory.defaultFileURL)
    }
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()
    XCTAssertFalse(delegate.debugRecentLessonsEnabled)

    delegate.debugRecordLesson(["a → b: why"])

    XCTAssertTrue(delegate.debugRecentLessonsEnabled)
  }
}
