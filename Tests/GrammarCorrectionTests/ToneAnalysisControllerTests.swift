import XCTest

@testable import GrammarCorrection

@MainActor
final class ToneAnalysisControllerTests: XCTestCase {
  private final class StubFeedback: FeedbackPresenter {
    private(set) var infoMessages: [String] = []
    private(set) var errorMessages: [String] = []
    private(set) var successCount = 0

    func showSuccess() {
      successCount += 1
    }

    func showInfo(_ message: String) {
      infoMessages.append(message)
    }

    func showError(_ message: String) {
      errorMessages.append(message)
    }
  }

  private final class StubResultPresenter: ToneAnalysisResultPresenter {
    private(set) var shownResults: [ToneAnalysisResult] = []
    private(set) var shownErrors: [String] = []

    var onError: ((String) -> Void)?

    func showResult(_ result: ToneAnalysisResult) {
      shownResults.append(result)
    }

    func showError(_ message: String) {
      shownErrors.append(message)
      onError?(message)
    }

    func dismiss() {}
  }

  private final class StubKeyboard: KeyboardControlling {
    var isTrusted: Bool
    private(set) var commandCCount = 0

    init(isTrusted: Bool) {
      self.isTrusted = isTrusted
    }

    func isAccessibilityTrusted(prompt: Bool) -> Bool {
      isTrusted
    }

    func sendCommandA() {}

    func sendCommandC() {
      commandCCount += 1
    }

    func sendCommandV() {}
  }

  private final class StubPasteboard: PasteboardControlling {
    private var waitResults: [Result<String, Error>]
    private var changeCountValue = 0
    private(set) var waitCallCount = 0

    init(waitResults: [Result<String, Error>] = []) {
      self.waitResults = waitResults
    }

    func snapshot() -> PasteboardController.Snapshot {
      PasteboardController.Snapshot(items: [])
    }

    func restore(_ snapshot: PasteboardController.Snapshot) {}

    func setString(_ string: String) {
      changeCountValue += 1
    }

    var changeCount: Int {
      changeCountValue
    }

    func waitForCopiedString(
      after previousChangeCount: Int,
      excluding excluded: String?,
      timeout: Duration
    ) async throws -> String {
      waitCallCount += 1
      guard !waitResults.isEmpty else {
        return ""
      }
      let result = waitResults.removeFirst()
      switch result {
      case .success(let value):
        return value
      case .failure(let error):
        throw error
      }
    }
  }

  private struct SlowToneAnalyzer: ToneAnalyzer, Sendable {
    let delay: Duration

    func analyze(_ text: String) async throws -> ToneAnalysisResult {
      try await Task.sleep(for: delay)
      return ToneAnalysisResult(
        tone: .neutral,
        sentiment: .neutral,
        formality: .casual,
        explanation: "ok"
      )
    }
  }

  private struct ImmediateToneAnalyzer: ToneAnalyzer, Sendable {
    func analyze(_ text: String) async throws -> ToneAnalysisResult {
      ToneAnalysisResult(
        tone: .neutral,
        sentiment: .neutral,
        formality: .casual,
        explanation: "ok"
      )
    }
  }

  private static let fastTimings = ToneAnalysisController.Timings(
    activationDelay: .zero,
    copySettleDelay: .zero,
    copyTimeout: .milliseconds(10)
  )

  func testAnalyzeSelectionTimesOut() async {
    let completion = expectation(description: "tone timeout surfaced")
    let feedback = StubFeedback()
    let presenter = StubResultPresenter()
    presenter.onError = { message in
      if message.contains("timed out") {
        completion.fulfill()
      }
    }

    let controller = ToneAnalysisController(
      analyzer: SlowToneAnalyzer(delay: .milliseconds(300)),
      feedback: feedback,
      resultPresenter: presenter,
      timings: Self.fastTimings,
      operationTimeout: .milliseconds(60),
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success("This is enough text")])
    )

    controller.analyzeSelection()

    await fulfillment(of: [completion], timeout: 1.0)
    XCTAssertTrue(presenter.shownErrors.contains(where: { $0.contains("timed out") }))
    XCTAssertTrue(presenter.shownResults.isEmpty, "No success result should be shown after timeout")
  }

  func testNearDeadlineCopyFailsWithTimeoutBeforeIssuingCopyCommand() async {
    let completion = expectation(description: "tone timeout surfaced")
    let feedback = StubFeedback()
    let presenter = StubResultPresenter()
    presenter.onError = { message in
      if message.contains("timed out") {
        completion.fulfill()
      }
    }

    let keyboard = StubKeyboard(isTrusted: true)
    let pasteboard = StubPasteboard(waitResults: [.success("This is enough text")])
    let controller = ToneAnalysisController(
      analyzer: ImmediateToneAnalyzer(),
      feedback: feedback,
      resultPresenter: presenter,
      timings: ToneAnalysisController.Timings(
        activationDelay: .zero,
        copySettleDelay: .zero,
        copyTimeout: .milliseconds(900)
      ),
      operationTimeout: .milliseconds(20),
      keyboard: keyboard,
      pasteboard: pasteboard
    )

    controller.analyzeSelection()

    await fulfillment(of: [completion], timeout: 1.0)
    XCTAssertEqual(keyboard.commandCCount, 0, "Should not issue copy command when deadline is already too close")
    XCTAssertEqual(pasteboard.waitCallCount, 0, "Should not wait on pasteboard when deadline is already too close")
    XCTAssertTrue(presenter.shownResults.isEmpty)
  }
}
