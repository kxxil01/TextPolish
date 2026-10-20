import XCTest

@testable import GrammarCorrection

/// Polish shows which style ran, and its settings carry over from the old Correct Selection shortcut.
extension CorrectionControllerTests {

  @MainActor
  func testNaturalPolishShowsRewriteFeedback() async {
    let feedback = await polishFeedback(style: .clarify)

    XCTAssertEqual(feedback.rewriteSuccessCount, 1)
    XCTAssertEqual(feedback.successCount, 0)
  }

  @MainActor
  func testMinimalPolishShowsCorrectFeedback() async {
    let feedback = await polishFeedback(style: .minimal)

    XCTAssertEqual(feedback.successCount, 1)
    XCTAssertEqual(feedback.rewriteSuccessCount, 0)
  }

  @MainActor
  private func polishFeedback(style: CorrectionStyle) async -> StubFeedback {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { finished.fulfill() }
    let controller = CorrectionController(
      corrector: ExclaimingCorrector(),
      feedback: feedback,
      settings: Settings.loadOrCreateDefault(),
      timings: Self.fastTimings,
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success("hello")])
    )

    controller.polish(style: style)

    await fulfillment(of: [finished], timeout: 1.0)
    return feedback
  }
}

private struct ExclaimingCorrector: GrammarCorrector {
  func correct(_ text: String) async throws -> String {
    text + "!"
  }
}

final class PolishSettingsTests: XCTestCase {
  func testPolishStyleDefaultsToNatural() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

    XCTAssertEqual(settings.polishStyle, .natural)
    XCTAssertEqual(settings.polishStyle.correctionStyle, .clarify)
  }

  func testUnknownPolishStyleFallsBackToNatural() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"polishStyle":"fancy"}"#.utf8))

    XCTAssertEqual(settings.polishStyle, .natural)
  }

  func testMinimalPolishStyleRoundTrips() throws {
    var settings = Settings()
    settings.polishStyle = .minimal

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

    XCTAssertEqual(decoded.polishStyle, .minimal)
    XCTAssertEqual(decoded.polishStyle.correctionStyle, .minimal)
  }

  func testCustomCorrectSelectionShortcutBecomesPolishShortcut() throws {
    let json = #"{"hotKeyCorrectSelection":{"keyCode":14,"modifiers":2304},"hotKeyCorrectAll":{"keyCode":5,"modifiers":6400}}"#

    let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))

    XCTAssertEqual(settings.hotKeyPolish, Settings.HotKey(keyCode: 14, modifiers: 2304))
  }
}
