import Carbon
import XCTest

@testable import GrammarCorrection

/// Rewrite Selection runs the correction pipeline with the clarify style.
extension CorrectionControllerTests {

  @MainActor
  func testRewriteSelectionUsesClarifyStyle() async {
    let styles = await runCorrection { $0.rewriteSelection() }

    XCTAssertEqual(styles, [.clarify])
  }

  @MainActor
  func testCorrectSelectionKeepsMinimalStyle() async {
    let styles = await runCorrection { $0.correctSelection() }

    XCTAssertEqual(styles, [.minimal])
  }

  @MainActor
  private func runCorrection(_ start: (CorrectionController) -> Void) async -> [CorrectionStyle] {
    let completion = expectation(description: "correction finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { completion.fulfill() }
    let recorder = StyleRecordingCorrector()
    let controller = CorrectionController(
      corrector: recorder,
      feedback: feedback,
      settings: Settings.loadOrCreateDefault(),
      timings: Self.fastTimings,
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success("hello")])
    )

    start(controller)

    await fulfillment(of: [completion], timeout: 1.0)
    return await recorder.styles.value
  }
}

private final class StyleRecordingCorrector: GrammarCorrector, @unchecked Sendable {
  let styles = StyleLog()

  func correct(_ text: String) async throws -> String {
    try await correct(text, style: .minimal)
  }

  func correct(_ text: String, style: CorrectionStyle) async throws -> String {
    await styles.append(style)
    return text + "!"
  }
}

private actor StyleLog {
  private(set) var value: [CorrectionStyle] = []

  func append(_ style: CorrectionStyle) {
    value.append(style)
  }
}

final class RewriteHotKeySettingsTests: XCTestCase {
  func testMissingRewriteHotKeyDecodesToDefault() throws {
    let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

    XCTAssertEqual(settings.hotKeyRewriteSelection, .rewriteSelectionDefault)
  }

  func testMissingRewriteHotKeyAvoidsComboAlreadyInUse() throws {
    let taken = Settings.HotKey.rewriteSelectionDefault
    let json = try JSONEncoder().encode(["hotKeyAnalyzeTone": taken])

    let settings = try JSONDecoder().decode(Settings.self, from: json)

    XCTAssertNotEqual(settings.hotKeyRewriteSelection, taken)
    XCTAssertEqual(settings.hotKeyRewriteSelection.keyCode, UInt32(kVK_ANSI_R))
    XCTAssertTrue(settings.hotKeyRewriteSelection.modifiers & UInt32(shiftKey) != 0)
  }

  func testCustomRewriteHotKeyRoundTrips() throws {
    var settings = Settings()
    settings.hotKeyRewriteSelection = Settings.HotKey(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(cmdKey | optionKey))

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

    XCTAssertEqual(decoded.hotKeyRewriteSelection, settings.hotKeyRewriteSelection)
  }
}
