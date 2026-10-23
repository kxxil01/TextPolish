import AppKit
import XCTest

@testable import GrammarCorrection

/// When every attempt fails a check a person can judge, the last result is offered for review instead of nothing.
final class StuckPolishReviewTests: XCTestCase {
  func testOnlyChecksAPersonCanJudgeAreOffered() {
    XCTAssertNotNil(RejectedCandidate(text: "a", reason: .numbersChanged(["8"])))
    XCTAssertNotNil(RejectedCandidate(text: "a", reason: .overRewrite))
    XCTAssertNotNil(RejectedCandidate(text: "a", reason: .lineStructureChanged))
    XCTAssertNil(RejectedCandidate(text: "a", reason: .refusal))
    XCTAssertNil(RejectedCandidate(text: "a", reason: .outputTooLong))
    XCTAssertNil(RejectedCandidate(text: "a", reason: .placeholdersMissing), "Never offer a result that lost code or links")
  }

  func testWarningsSayWhatWasFlagged() {
    XCTAssertEqual(
      RejectedCandidate(text: "a", reason: .numbersChanged(["8", "2.500.000"]))?.warning,
      "Check this: \"8\", \"2.500.000\" is not in the result. Paste only if the change is right."
    )
    XCTAssertTrue(RejectedCandidate(text: "a", reason: .overRewrite)?.warning.contains("changes more than") == true)
    XCTAssertTrue(RejectedCandidate(text: "a", reason: .lineStructureChanged)?.warning.contains("line breaks") == true)
  }

  @MainActor
  func testPanelShowsTheWarningAndReturnDoesNotPaste() async {
    let panel = PolishReviewPanel()
    let decision = Task {
      await panel.review(original: "a 8", polished: "a", style: .clarify, choices: [], warning: "Check this: \"8\" is not in the result.")
    }
    for _ in 0..<200 where !panel.debugIsShowing {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }

    XCTAssertEqual(panel.debugWarning, "Check this: \"8\" is not in the result.")
    panel.debugChoose(paste: false)
    _ = await decision.value
  }
}

extension CorrectorRetryAndPlaceholderTests {
  func testEveryAttemptRejectedLeavesTheLastResultForReview() async throws {
    MockURLProtocol.handler = { request in
      let body = #"{"choices":[{"message":{"content":"pls transfer 2,500,000 rupiah before Friday."}}]}"#
      return Self.httpResponse(for: request, statusCode: 200, body: body)
    }
    let settings = Settings(
      provider: .openAI, requestTimeoutSeconds: 1, openAIApiKey: "test-key", openAIBaseURL: "https://mock.local", openAIMaxAttempts: 2
    )
    let corrector = try OpenAICorrector(settings: settings, session: Self.makeMockSession())

    _ = try? await corrector.correct("pls transfer 2.500.000 rupiah before Friday", style: .clarify)

    XCTAssertEqual(corrector.lastRejected?.text, "pls transfer 2,500,000 rupiah before Friday.")
    XCTAssertEqual(corrector.lastRejected?.reason, .numbersChanged(["2.500.000"]))
  }
}

extension CorrectionControllerTests {
  @MainActor
  func testRejectedResultIsReviewedEvenWithPreviewOffThenPasted() async {
    let run = await runStuck(approve: true)

    XCTAssertEqual(run.reviewer.reviewed.first?.polished, "its gone after i migrate everything")
    XCTAssertEqual(run.reviewer.warnings, ["Check this: \"8\" is not in the result. Paste only if the change is right."])
    XCTAssertTrue(run.pasteboard.setStringCalls.contains("its gone after i migrate everything"))
    XCTAssertEqual(run.keyboard.commandVCount, 1)
  }

  @MainActor
  func testCancelingAFlaggedResultPastesNothing() async {
    let run = await runStuck(approve: false)

    XCTAssertEqual(run.keyboard.commandVCount, 0)
    XCTAssertEqual(run.feedback.infoMessages, ["Canceled"])
  }

  @MainActor
  func testWithoutAReviewerTheErrorStands() async {
    let failed = expectation(description: "error shown")
    let feedback = StubFeedback()
    feedback.onError = { _ in failed.fulfill() }
    let keyboard = StubKeyboard(isTrusted: true)
    let controller = CorrectionController(
      corrector: StuckCorrector(),
      feedback: feedback,
      settings: Settings(),
      timings: Self.fastTimings,
      keyboard: keyboard,
      pasteboard: StubPasteboard(waitResults: [.success("its gone after i migrate everytgh8ng")])
    )

    controller.polish(style: .clarify)

    await fulfillment(of: [failed], timeout: 1.0)
    XCTAssertEqual(keyboard.commandVCount, 0, "Nothing flagged is pasted without a person seeing it")
  }

  @MainActor
  private func runStuck(approve: Bool) async -> PreviewRun {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { finished.fulfill() }
    feedback.onInfo = { _ in finished.fulfill() }
    let keyboard = StubKeyboard(isTrusted: true)
    let pasteboard = StubPasteboard(waitResults: [.success("its gone after i migrate everytgh8ng")])
    let reviewer = StubReviewer(approve: approve)
    let controller = CorrectionController(
      corrector: StuckCorrector(),
      feedback: feedback,
      settings: Settings(),
      timings: Self.fastTimings,
      keyboard: keyboard,
      pasteboard: pasteboard,
      reviewer: reviewer
    )

    controller.polish(style: .clarify)

    await fulfillment(of: [finished], timeout: 1.0)
    return PreviewRun(keyboard: keyboard, pasteboard: pasteboard, feedback: feedback, reviewer: reviewer)
  }
}

/// Fails every attempt on the number check, keeping the last result it rejected.
private final class StuckCorrector: GrammarCorrector, RejectionReporting, @unchecked Sendable {
  struct Rejected: Error {}

  private(set) var lastRejected: RejectedCandidate?

  func correct(_ text: String) async throws -> String {
    lastRejected = RejectedCandidate(text: "its gone after i migrate everything", reason: .numbersChanged(["8"]))
    throw Rejected()
  }
}
