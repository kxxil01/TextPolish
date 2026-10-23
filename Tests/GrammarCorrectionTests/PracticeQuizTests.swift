import AppKit
import XCTest

@testable import GrammarCorrection

/// Practice: a short round from the writer's own mistakes.
final class PracticeQuizTests: XCTestCase {
  private let items = [
    PracticeItem(before: "needsed", after: "needed", reason: "spelling"),
    PracticeItem(before: "already check", after: "already checked", reason: "past participle"),
  ]

  func testScoresEachQuestionOnceAndFinishes() {
    var quiz = PracticeQuiz(items: items)

    XCTAssertEqual(quiz.current?.before, "needsed")
    XCTAssertTrue(quiz.check("  Needed. "), "Case, spacing, and final punctuation do not count")
    XCTAssertFalse(quiz.check("needed"), "A question counts once")
    quiz.next()
    XCTAssertFalse(quiz.check("already check"))
    quiz.next()

    XCTAssertTrue(quiz.isFinished)
    XCTAssertEqual(quiz.score, 1)
  }

  func testNextWaitsForAnAnswerAndRoundsAreShort() {
    var quiz = PracticeQuiz(items: items)
    quiz.next()
    XCTAssertEqual(quiz.index, 0)

    let many = (0..<9).map { PracticeItem(before: "a\($0)", after: "b\($0)", reason: nil) }
    XCTAssertEqual(PracticeQuiz(items: many).items.count, PracticeQuiz.roundSize)
  }

  func testNormalizationIgnoresQuotesAndCurlyApostrophes() {
    XCTAssertEqual(PracticeQuiz.normalized("\u{201C}I\u{2019}ve  checked!\u{201D}"), "i've checked")
  }

  @MainActor
  func testItemsPutRepeatedMistakesFirstThenRecentOnesOnceEach() {
    let history = makeHistory()
    history.add(["teh → the: spelling", "pls → please: spell out"])
    history.add(["teh → the: spelling", String(repeating: "x", count: 10) + " → " + String(repeating: "y", count: 70)])
    history.add(["already check → already checked: past participle"])

    let practice = history.practiceItems()

    XCTAssertEqual(practice.map(\.before), ["teh", "already check", "pls"], "Repeated first, each once, long ones skipped")
  }

  @MainActor
  func testWindowRunsARoundAndShowsTheScore() {
    let history = makeHistory()
    history.add(["needsed → needed: spelling"])
    let window = PracticeWindow(history: history)
    window.debugStartRound()

    XCTAssertEqual(window.debugProgress, "Question 1 of 1")
    XCTAssertEqual(window.debugPhrase, "needsed")
    window.debugAnswer("neded")
    XCTAssertEqual(window.debugResult, "Answer: needed: spelling")
    window.debugNext()
    XCTAssertEqual(window.debugPhrase, "You got 0 of 1 right.")
  }

  @MainActor
  func testWindowExplainsWhenThereIsNothingToPractice() {
    let window = PracticeWindow(history: makeHistory())
    window.debugStartRound()

    XCTAssertTrue(window.debugPhrase.hasPrefix("Nothing to practice yet."))
  }

  @MainActor
  private func makeHistory() -> LessonHistory {
    let name = "lessons-\(UUID().uuidString)"
    addTeardownBlock {
      for suffix in ["", "-mistakes", "-weeks"] {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("\(name)\(suffix).json"))
      }
    }
    return LessonHistory(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json"))
  }
}
