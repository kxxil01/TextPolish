import AppKit
import XCTest

@testable import GrammarCorrection

final class WordDiffTests: XCTestCase {
  func testTokensSplitWordsSpacesAndPunctuation() {
    XCTAssertEqual(WordDiff.tokens(in: "I've done it, ok?"), ["I've", " ", "done", " ", "it", ",", " ", "ok", "?"])
  }

  func testIdenticalTextIsOneUnchangedRun() {
    XCTAssertEqual(WordDiff.changes(from: "same text", to: "same text"), [.same("same text")])
  }

  func testReplacedWordsShowAsRemovedThenAdded() {
    let changes = WordDiff.changes(from: "added status progress to it", to: "added a progress status to it")

    XCTAssertEqual(changes.first, .same("added "))
    XCTAssertEqual(rebuilt(changes, keeping: .removed), "added status progress to it")
    XCTAssertEqual(rebuilt(changes, keeping: .added), "added a progress status to it")
  }

  func testRemovedTextIsStruckThrough() {
    let text = WordDiff.attributedString(from: [.same("a "), .removed("b"), .added("c")], font: .systemFont(ofSize: 12))
    let removedStyle = text.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) as? Int
    let addedStyle = text.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int

    XCTAssertEqual(text.string, "a b c", "A space keeps the removed and added words apart")
    XCTAssertEqual(removedStyle, NSUnderlineStyle.single.rawValue)
    XCTAssertNil(addedStyle)
  }

  private enum Side { case removed, added }

  /// Rebuilds one side of the diff: the original (unchanged + removed) or the result (unchanged + added).
  private func rebuilt(_ changes: [WordDiff.Change], keeping side: Side) -> String {
    changes.map { change -> String in
      switch (change, side) {
      case let (.same(text), _): return text
      case let (.removed(text), .removed): return text
      case let (.added(text), .added): return text
      default: return ""
      }
    }.joined()
  }
}

final class PolishReviewPanelTests: XCTestCase {
  @MainActor
  func testPanelReturnsTheChosenButton() async {
    for approve in [true, false] {
      let panel = PolishReviewPanel()
      let choice = Task { await panel.review(original: "pls check", polished: "please check") }
      await waitUntil { panel.debugIsShowing }

      XCTAssertTrue(panel.debugStaysOverOtherApps, "The panel must not hide behind the app being polished")
      panel.debugChoose(paste: approve)

      let approved = await choice.value
      XCTAssertEqual(approved, approve)
      XCTAssertFalse(panel.debugIsShowing)
    }
  }

  @MainActor
  func testCancelingPolishClosesThePanel() async {
    let panel = PolishReviewPanel()
    let choice = Task { await panel.review(original: "a", polished: "b") }
    await waitUntil { panel.debugIsShowing }

    choice.cancel()

    let approved = await choice.value
    XCTAssertFalse(approved)
    await waitUntil { !panel.debugIsShowing }
    XCTAssertFalse(panel.debugIsShowing)
  }

  @MainActor
  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
  }
}

/// With Preview Before Paste on, Polish waits for the user before replacing the text.
extension CorrectionControllerTests {
  @MainActor
  final class StubReviewer: PolishReviewing {
    var approve: Bool
    private(set) var reviewed: [(original: String, polished: String)] = []

    init(approve: Bool) {
      self.approve = approve
    }

    func review(original: String, polished: String) async -> Bool {
      reviewed.append((original, polished))
      return approve
    }
  }

  @MainActor
  func testPreviewApprovedPastesThePolishedText() async {
    let run = await runPreview(approve: true)
    let (keyboard, pasteboard, feedback, reviewer) = (run.keyboard, run.pasteboard, run.feedback, run.reviewer)

    XCTAssertEqual(reviewer.reviewed.first?.original, "hello")
    XCTAssertEqual(reviewer.reviewed.first?.polished, "hello!")
    XCTAssertEqual(keyboard.commandVCount, 1)
    XCTAssertTrue(pasteboard.setStringCalls.contains("hello!"))
    XCTAssertEqual(feedback.successCount, 1)
  }

  @MainActor
  func testPreviewCanceledLeavesTheTextAlone() async {
    let run = await runPreview(approve: false)
    let (keyboard, pasteboard, feedback, reviewer) = (run.keyboard, run.pasteboard, run.feedback, run.reviewer)

    XCTAssertEqual(reviewer.reviewed.count, 1)
    XCTAssertEqual(keyboard.commandVCount, 0, "Nothing is pasted")
    XCTAssertFalse(pasteboard.setStringCalls.contains("hello!"))
    XCTAssertEqual(pasteboard.restoreCallCount, 1, "The clipboard goes back to what it held")
    XCTAssertEqual(feedback.infoMessages, ["Canceled"])
  }

  @MainActor
  func testPreviewIsSkippedWhenTheSettingIsOff() async {
    let run = await runPreview(approve: false, enabled: false)
    let (keyboard, reviewer) = (run.keyboard, run.reviewer)

    XCTAssertTrue(reviewer.reviewed.isEmpty)
    XCTAssertEqual(keyboard.commandVCount, 1)
  }

  struct PreviewRun {
    let keyboard: StubKeyboard
    let pasteboard: StubPasteboard
    let feedback: StubFeedback
    let reviewer: StubReviewer
  }

  @MainActor
  private func runPreview(approve: Bool, enabled: Bool = true) async -> PreviewRun {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { finished.fulfill() }
    feedback.onInfo = { _ in finished.fulfill() }
    let keyboard = StubKeyboard(isTrusted: true)
    let pasteboard = StubPasteboard(waitResults: [.success("hello")])
    let reviewer = StubReviewer(approve: approve)
    var settings = Settings()
    settings.previewBeforePaste = enabled
    let controller = CorrectionController(
      corrector: PreviewExclaimingCorrector(),
      feedback: feedback,
      settings: settings,
      timings: Self.fastTimings,
      keyboard: keyboard,
      pasteboard: pasteboard,
      reviewer: reviewer
    )

    controller.polish(style: .minimal)

    await fulfillment(of: [finished], timeout: 1.0)
    return PreviewRun(keyboard: keyboard, pasteboard: pasteboard, feedback: feedback, reviewer: reviewer)
  }
}

private struct PreviewExclaimingCorrector: GrammarCorrector {
  func correct(_ text: String) async throws -> String {
    text + "!"
  }
}
