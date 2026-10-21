import AppKit
import XCTest

@testable import GrammarCorrection

/// Learn mode explanations are kept so they can be reviewed later from Recent Lessons.
final class LessonHistoryTests: XCTestCase {
  private func temporaryFile() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
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
