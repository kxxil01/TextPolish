import XCTest

@testable import GrammarCorrection

final class CorrectionControllerTests: XCTestCase {
  @MainActor
  private final class StubFeedback: FeedbackPresenter {
    private(set) var infoMessages: [String] = []

    func showSuccess() {}

    func showInfo(_ message: String) {
      infoMessages.append(message)
    }

    func showError(_ message: String) {}
  }

  @MainActor
  private final class StubKeyboard: KeyboardControlling {
    var isTrusted: Bool

    init(isTrusted: Bool) {
      self.isTrusted = isTrusted
    }

    func isAccessibilityTrusted(prompt: Bool) -> Bool {
      isTrusted
    }

    func sendCommandA() {}
    func sendCommandC() {}
    func sendCommandV() {}
  }

  @MainActor
  private final class StubPasteboard: PasteboardControlling {
    func snapshot() -> PasteboardController.Snapshot {
      PasteboardController.Snapshot(items: [])
    }

    func restore(_ snapshot: PasteboardController.Snapshot) {}

    func setString(_ string: String) {}

    var changeCount: Int {
      0
    }

    func waitForCopiedString(
      after previousChangeCount: Int,
      excluding excluded: String?,
      timeout: Duration
    ) async throws -> String {
      ""
    }
  }

  private struct NoopCorrector: GrammarCorrector, Sendable {
    func correct(_ text: String) async throws -> String {
      text
    }
  }

  @MainActor
  func testBusyFeedbackThrottlesOnRepeatedHotkeys() async {
    let feedback = StubFeedback()
    let controller = CorrectionController(
      corrector: NoopCorrector(),
      feedback: feedback,
      keyboard: StubKeyboard(isTrusted: false),
      pasteboard: StubPasteboard()
    )

    controller.correctSelection()
    controller.correctSelection()
    controller.correctSelection()

    XCTAssertEqual(feedback.infoMessages, ["Correction in progress"])
    await Task.yield()
  }

  func testFeedbackCooldownAllowsAfterInterval() {
    var gate = FeedbackCooldown(cooldown: .milliseconds(100))
    let start = ContinuousClock.now

    XCTAssertTrue(gate.shouldShow(now: start))
    XCTAssertFalse(gate.shouldShow(now: start + .milliseconds(50)))
    XCTAssertTrue(gate.shouldShow(now: start + .milliseconds(100)))
  }

  func testTimingsInitFromSettings() {
    let settings = Settings(
      activationDelayMilliseconds: 10,
      selectAllDelayMilliseconds: 20,
      copySettleDelayMilliseconds: 30,
      copyTimeoutMilliseconds: 40,
      pasteSettleDelayMilliseconds: 50,
      postPasteDelayMilliseconds: 60
    )

    let timings = CorrectionController.Timings(settings: settings)

    XCTAssertEqual(timings.activationDelay, .milliseconds(10))
    XCTAssertEqual(timings.selectAllDelay, .milliseconds(20))
    XCTAssertEqual(timings.copySettleDelay, .milliseconds(30))
    XCTAssertEqual(timings.copyTimeout, .milliseconds(40))
    XCTAssertEqual(timings.pasteSettleDelay, .milliseconds(50))
    XCTAssertEqual(timings.postPasteDelay, .milliseconds(60))
  }

  func testTimingsClampNegativeValues() {
    let settings = Settings(
      activationDelayMilliseconds: -1,
      selectAllDelayMilliseconds: -2,
      copySettleDelayMilliseconds: -3,
      copyTimeoutMilliseconds: -4,
      pasteSettleDelayMilliseconds: -5,
      postPasteDelayMilliseconds: -6
    )

    let timings = CorrectionController.Timings(settings: settings)

    XCTAssertEqual(timings.activationDelay, .milliseconds(0))
    XCTAssertEqual(timings.selectAllDelay, .milliseconds(0))
    XCTAssertEqual(timings.copySettleDelay, .milliseconds(0))
    XCTAssertEqual(timings.copyTimeout, .milliseconds(0))
    XCTAssertEqual(timings.pasteSettleDelay, .milliseconds(0))
    XCTAssertEqual(timings.postPasteDelay, .milliseconds(0))
  }
}
