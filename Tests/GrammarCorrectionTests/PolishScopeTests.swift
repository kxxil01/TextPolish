import XCTest

@testable import GrammarCorrection

/// Polish works on the selection, or on the whole field when nothing is selected.
extension CorrectionControllerTests {

  @MainActor
  func testPolishWithSelectionCopiesSelectionOnly() async {
    let run = await runPolish(selection: .selected, copies: [.success("hello")])

    XCTAssertEqual(run.keyboard.commandACount, 0)
    XCTAssertEqual(run.keyboard.commandVCount, 1)
    XCTAssertEqual(run.feedback.successCount, 1)
  }

  @MainActor
  func testPolishWithNothingSelectedSelectsAllFirst() async {
    let run = await runPolish(selection: .nothingSelected, copies: [.success("hello")])

    XCTAssertEqual(run.keyboard.commandACount, 1)
    XCTAssertEqual(run.pasteboard.waitCallCount, 1)
    XCTAssertEqual(run.keyboard.commandVCount, 1)
  }

  @MainActor
  func testPolishFallsBackToWholeFieldWhenNothingCopiesAndSelectionIsUnknown() async {
    let noChange = PasteboardController.PasteboardError.noChange
    let run = await runPolish(selection: .unknown, copies: [.failure(noChange), .failure(noChange), .success("hello")])

    XCTAssertEqual(run.keyboard.commandACount, 1, "Select-all only after the selection copy failed")
    XCTAssertEqual(run.pasteboard.waitCallCount, 3)
    XCTAssertEqual(run.keyboard.commandVCount, 1)
  }

  @MainActor
  func testPolishDoesNotReplaceAKnownSelectionWithTheWholeField() async {
    let noChange = PasteboardController.PasteboardError.noChange
    let run = await runPolish(selection: .selected, copies: [.failure(noChange), .failure(noChange)], expectSuccess: false)

    XCTAssertEqual(run.keyboard.commandACount, 0)
    XCTAssertEqual(run.keyboard.commandVCount, 0)
    XCTAssertFalse(run.feedback.errorMessages.isEmpty)
  }

  @MainActor
  func testPolishPassesTheChosenStyle() async {
    let recorder = PolishStyleRecorder()
    _ = await runPolish(selection: .selected, copies: [.success("hello")], style: .clarify, corrector: recorder)

    let styles = await recorder.styles.value
    XCTAssertEqual(styles, [.clarify])
  }

  // MARK: - Helpers

  private struct PolishRun {
    let keyboard: StubKeyboard
    let pasteboard: StubPasteboard
    let feedback: StubFeedback
  }

  @MainActor
  private func runPolish(
    selection: SelectionState,
    copies: [Result<String, Error>],
    style: CorrectionStyle = .minimal,
    corrector: GrammarCorrector = PolishStyleRecorder(),
    expectSuccess: Bool = true
  ) async -> PolishRun {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { if expectSuccess { finished.fulfill() } }
    feedback.onError = { _ in if !expectSuccess { finished.fulfill() } }
    let keyboard = StubKeyboard(isTrusted: true)
    let pasteboard = StubPasteboard(waitResults: copies)
    let controller = CorrectionController(
      corrector: corrector,
      feedback: feedback,
      settings: Settings.loadOrCreateDefault(),
      timings: Self.fastTimings,
      keyboard: keyboard,
      pasteboard: pasteboard,
      selectionStateProvider: { _ in selection }
    )

    controller.polish(style: style)

    await fulfillment(of: [finished], timeout: 2.0)
    return PolishRun(keyboard: keyboard, pasteboard: pasteboard, feedback: feedback)
  }
}

private final class PolishStyleRecorder: GrammarCorrector, @unchecked Sendable {
  let styles = PolishStyleLog()

  func correct(_ text: String) async throws -> String {
    try await correct(text, style: .minimal)
  }

  func correct(_ text: String, style: CorrectionStyle) async throws -> String {
    await styles.append(style)
    return text + "!"
  }
}

private actor PolishStyleLog {
  private(set) var value: [CorrectionStyle] = []

  func append(_ style: CorrectionStyle) {
    value.append(style)
  }
}
