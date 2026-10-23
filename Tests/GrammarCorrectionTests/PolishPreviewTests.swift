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
  private let choices = [
    PolishStyleChoice(name: "Natural", style: .clarify),
    PolishStyleChoice(name: "Formal", style: .formal),
  ]

  @MainActor
  func testPanelReturnsTheChosenButton() async {
    for approve in [true, false] {
      let panel = PolishReviewPanel()
      let choice = Task { await panel.review(original: "pls check", polished: "please check", style: .clarify, choices: choices) }
      await waitUntil { panel.debugIsShowing }

      XCTAssertTrue(panel.debugStaysOverOtherApps, "The panel must not hide behind the app being polished")
      XCTAssertEqual(panel.debugStyleNames, ["Natural", "Formal"])
      panel.debugChoose(paste: approve)

      let decision = await choice.value
      XCTAssertEqual(decision, approve ? .paste : .cancel)
      XCTAssertFalse(panel.debugIsShowing)
    }
  }

  @MainActor
  func testCancelingPolishClosesThePanel() async {
    let panel = PolishReviewPanel()
    let choice = Task { await panel.review(original: "a", polished: "b", style: .clarify, choices: choices) }
    await waitUntil { panel.debugIsShowing }

    choice.cancel()

    let decision = await choice.value
    XCTAssertEqual(decision, .cancel)
    await waitUntil { !panel.debugIsShowing }
    XCTAssertFalse(panel.debugIsShowing)
  }

  @MainActor
  func testTryAgainKeepsThePanelUpAndShowsTheNextVersion() async {
    let panel = PolishReviewPanel()
    let first = Task { await panel.review(original: "pls check", polished: "please check", style: .clarify, choices: choices) }
    await waitUntil { panel.debugIsShowing }

    panel.debugTryAgain()
    let firstDecision = await first.value
    XCTAssertEqual(firstDecision, .retry(.clarify))
    XCTAssertTrue(panel.debugIsShowing, "The panel stays while the next version is made")
    XCTAssertEqual(panel.debugText, "Polishing as Natural\u{2026}")

    let second = Task { await panel.review(original: "pls check", polished: "Please check.", style: .formal, choices: choices) }
    await waitUntil { panel.debugText?.contains("Please") == true }
    panel.debugChoose(paste: true)
    let secondDecision = await second.value
    XCTAssertEqual(secondDecision, .paste)
  }

  @MainActor
  func testChoosingAnotherStyleAsksForIt() async {
    let panel = PolishReviewPanel()
    let choice = Task { await panel.review(original: "pls check", polished: "please check", style: .clarify, choices: choices) }
    await waitUntil { panel.debugIsShowing }

    panel.debugChooseStyle(named: "Formal")

    let decision = await choice.value
    XCTAssertEqual(decision, .retry(.formal))
    panel.dismiss()
    XCTAssertFalse(panel.debugIsShowing)
  }

  @MainActor
  func testCancelWhileTryingAgainCancelsTheNextReview() async {
    let panel = PolishReviewPanel()
    let first = Task { await panel.review(original: "a", polished: "b", style: .clarify, choices: choices) }
    await waitUntil { panel.debugIsShowing }
    panel.debugTryAgain()
    _ = await first.value

    panel.debugChoose(paste: false)
    XCTAssertFalse(panel.debugIsShowing)

    let next = await panel.review(original: "a", polished: "c", style: .clarify, choices: choices)
    XCTAssertEqual(next, .cancel)
    XCTAssertFalse(panel.debugIsShowing, "The canceled run never shows again")
  }

  @MainActor
  func testTranslationShowsTheEnglishTextWithoutAStylePicker() async {
    let panel = PolishReviewPanel()
    let choice = Task {
      await panel.review(original: "tolong cek", polished: "please check", style: .translateToEnglish, choices: [])
    }
    await waitUntil { panel.debugIsShowing }

    XCTAssertEqual(panel.debugTitle, "Review Translation")
    XCTAssertEqual(panel.debugText, "please check")
    XCTAssertNil(panel.debugStyleNames)
    panel.debugChoose(paste: true)
    _ = await choice.value
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
    private var decisions: [PolishReviewDecision]
    private(set) var reviewed: [(original: String, polished: String, style: CorrectionStyle)] = []
    private(set) var offeredChoices: [[PolishStyleChoice]] = []
    private(set) var warnings: [String?] = []
    private(set) var dismissCount = 0

    init(approve: Bool) {
      decisions = [approve ? .paste : .cancel]
    }

    init(decisions: [PolishReviewDecision]) {
      self.decisions = decisions
    }

    func review(
      original: String,
      polished: String,
      style: CorrectionStyle,
      choices: [PolishStyleChoice],
      warning: String?
    ) async -> PolishReviewDecision {
      reviewed.append((original, polished, style))
      offeredChoices.append(choices)
      warnings.append(warning)
      return decisions.isEmpty ? .cancel : decisions.removeFirst()
    }

    func dismiss() {
      dismissCount += 1
    }
  }

  @MainActor
  func testPreviewApprovedPastesThePolishedText() async {
    let run = await runPreview(reviewer: StubReviewer(approve: true))
    let (keyboard, pasteboard, feedback, reviewer) = (run.keyboard, run.pasteboard, run.feedback, run.reviewer)

    XCTAssertEqual(reviewer.reviewed.first?.original, "hello")
    XCTAssertEqual(reviewer.reviewed.first?.polished, "hello!")
    XCTAssertEqual(reviewer.offeredChoices.first?.map(\.name), ["Natural", "Minimal", "Shorter", "Formal", "Friendly"])
    XCTAssertEqual(keyboard.commandVCount, 1)
    XCTAssertTrue(pasteboard.setStringCalls.contains("hello!"))
    XCTAssertEqual(feedback.successCount, 1)
  }

  @MainActor
  func testPreviewCanceledLeavesTheTextAlone() async {
    let run = await runPreview(reviewer: StubReviewer(approve: false))
    let (keyboard, pasteboard, feedback, reviewer) = (run.keyboard, run.pasteboard, run.feedback, run.reviewer)

    XCTAssertEqual(reviewer.reviewed.count, 1)
    XCTAssertEqual(keyboard.commandVCount, 0, "Nothing is pasted")
    XCTAssertFalse(pasteboard.setStringCalls.contains("hello!"))
    XCTAssertEqual(pasteboard.restoreCallCount, 1, "The clipboard goes back to what it held")
    XCTAssertEqual(feedback.infoMessages, ["Canceled"])
  }

  @MainActor
  func testPreviewIsSkippedWhenTheSettingIsOff() async {
    let run = await runPreview(reviewer: StubReviewer(approve: false), enabled: false)
    let (keyboard, reviewer) = (run.keyboard, run.reviewer)

    XCTAssertTrue(reviewer.reviewed.isEmpty)
    XCTAssertEqual(keyboard.commandVCount, 1)
  }

  @MainActor
  func testAnotherStyleInThePreviewPolishesTheOriginalAgain() async {
    let corrector = PreviewStyleCorrector()
    var records: [PolishRecord] = []
    let run = await runPreview(
      reviewer: StubReviewer(decisions: [.retry(.formal), .paste]),
      corrector: corrector,
      onPolished: { records.append($0) }
    )

    XCTAssertEqual(corrector.styles, [.minimal, .formal])
    XCTAssertEqual(run.reviewer.reviewed.map(\.polished), ["hello (minimal)", "hello (formal)"])
    XCTAssertEqual(run.reviewer.reviewed.map(\.original), ["hello", "hello"], "Each try starts from the original")
    XCTAssertTrue(run.pasteboard.setStringCalls.contains("hello (formal)"))
    XCTAssertEqual(records.first?.style, .formal)
    XCTAssertEqual(records.first?.polished, "hello (formal)")
  }

  @MainActor
  func testAFailedTryClosesThePreviewAndReportsTheError() async {
    let corrector = PreviewStyleCorrector(failingStyle: .formal)
    let run = await runPreview(reviewer: StubReviewer(decisions: [.retry(.formal)]), corrector: corrector)

    XCTAssertEqual(run.reviewer.dismissCount, 1)
    XCTAssertEqual(run.keyboard.commandVCount, 0)
    XCTAssertEqual(run.feedback.errorMessages.count, 1)
  }

  @MainActor
  func testTranslationPreviewOffersNoStyles() async {
    let run = await runPreview(reviewer: StubReviewer(approve: true), style: .translateToEnglish)

    XCTAssertEqual(run.reviewer.offeredChoices, [[]])
  }

  struct PreviewRun {
    let keyboard: StubKeyboard
    let pasteboard: StubPasteboard
    let feedback: StubFeedback
    let reviewer: StubReviewer
  }

  @MainActor
  private func runPreview(
    reviewer: StubReviewer,
    enabled: Bool = true,
    style: CorrectionStyle = .minimal,
    corrector: GrammarCorrector = PreviewExclaimingCorrector(),
    onPolished: (@MainActor (PolishRecord) -> Void)? = nil
  ) async -> PreviewRun {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { finished.fulfill() }
    feedback.onInfo = { _ in finished.fulfill() }
    feedback.onError = { _ in finished.fulfill() }
    let keyboard = StubKeyboard(isTrusted: true)
    let pasteboard = StubPasteboard(waitResults: [.success("hello")])
    var settings = Settings()
    settings.previewBeforePaste = enabled
    let controller = CorrectionController(
      corrector: corrector,
      feedback: feedback,
      settings: settings,
      timings: Self.fastTimings,
      keyboard: keyboard,
      pasteboard: pasteboard,
      reviewer: reviewer,
      onPolished: onPolished
    )

    controller.polish(style: style)

    await fulfillment(of: [finished], timeout: 1.0)
    return PreviewRun(keyboard: keyboard, pasteboard: pasteboard, feedback: feedback, reviewer: reviewer)
  }
}

private struct PreviewExclaimingCorrector: GrammarCorrector {
  func correct(_ text: String) async throws -> String {
    text + "!"
  }
}

/// Marks each result with its style, and can fail one style.
private final class PreviewStyleCorrector: GrammarCorrector, @unchecked Sendable {
  struct Failure: Error {}

  private let lock = NSLock()
  private var recorded: [CorrectionStyle] = []
  private let failingStyle: CorrectionStyle?

  init(failingStyle: CorrectionStyle? = nil) {
    self.failingStyle = failingStyle
  }

  var styles: [CorrectionStyle] {
    lock.withLock { recorded }
  }

  func correct(_ text: String) async throws -> String {
    try await correct(text, style: .minimal)
  }

  func correct(_ text: String, style: CorrectionStyle) async throws -> String {
    lock.withLock { recorded.append(style) }
    if style == failingStyle {
      throw Failure()
    }
    return "\(text) (\(style))"
  }
}
