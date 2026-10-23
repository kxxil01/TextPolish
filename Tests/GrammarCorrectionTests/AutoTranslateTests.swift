import XCTest

@testable import GrammarCorrection

/// Polish translates text that is mostly Indonesian, so one shortcut works in both languages.
final class AutoTranslateTests: XCTestCase {
  func testRecognizesTheWritersIndonesianAndLeavesEnglishAlone() {
    for text in [
      "tolong cek laporan yang gw kirim kemarin ya, angka di halaman 3 kayaknya salah deh",
      "bro deploy nya udah done belum? soalnya client nanya terus dari pagi",
      "udah aku push ke main, cek PR nya ya",
    ] {
      XCTAssertTrue(LanguageDetector.isMostlyIndonesian(text), text)
    }
    for text in [
      "its not being used anymore after i migrate everytgh8ng to WIF = keyless auth",
      "the client keep asking about the invoice, pls send asap",
      "Gonna extend 1 week more of silence",
      "ok bro thanks",
      "oke siap",
    ] {
      XCTAssertFalse(LanguageDetector.isMostlyIndonesian(text), text)
    }
  }

  func testOnlyRewriteStylesTranslateAndTheSettingAndLanguageCanTurnItOff() {
    var settings = Settings()
    XCTAssertTrue(settings.autoTranslateIndonesian, "On by default")
    XCTAssertTrue(settings.translatesIndonesian(in: .clarify))
    XCTAssertTrue(settings.translatesIndonesian(in: .formal))
    XCTAssertFalse(settings.translatesIndonesian(in: .minimal), "Terminals and code editors use Minimal")
    XCTAssertFalse(settings.translatesIndonesian(in: .translateToEnglish))

    settings.correctionLanguage = .indonesian
    XCTAssertFalse(settings.translatesIndonesian(in: .clarify), "The writer chose to correct Indonesian")

    settings.correctionLanguage = .auto
    settings.autoTranslateIndonesian = false
    XCTAssertFalse(settings.translatesIndonesian(in: .clarify))
  }

  func testSettingRoundTripsAndOlderFilesHaveItOn() throws {
    var settings = Settings()
    settings.autoTranslateIndonesian = false
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    let older = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

    XCTAssertFalse(decoded.autoTranslateIndonesian)
    XCTAssertTrue(older.autoTranslateIndonesian)
  }
}

extension CorrectionControllerTests {
  @MainActor
  func testPolishTranslatesIndonesianInARewriteStyle() async {
    let styles = await polishedStyles(for: "oke nanti gw kirim sebelum jam 3 ya", style: .clarify, settings: Settings())
    XCTAssertEqual(styles, [.translateToEnglish])
  }

  @MainActor
  func testPolishKeepsItsStyleForEnglishMinimalOrWhenTurnedOff() async {
    var off = Settings()
    off.autoTranslateIndonesian = false
    let english = await polishedStyles(for: "the client keep asking about the invoice", style: .clarify, settings: Settings())
    let minimal = await polishedStyles(for: "oke nanti gw kirim sebelum jam 3 ya", style: .minimal, settings: Settings())
    let disabled = await polishedStyles(for: "oke nanti gw kirim sebelum jam 3 ya", style: .clarify, settings: off)

    XCTAssertEqual(english, [.clarify])
    XCTAssertEqual(minimal, [.minimal])
    XCTAssertEqual(disabled, [.clarify])
  }

  @MainActor
  private func polishedStyles(for text: String, style: CorrectionStyle, settings: Settings) async -> [CorrectionStyle] {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { finished.fulfill() }
    let corrector = TranslateRecordingCorrector()
    let controller = CorrectionController(
      corrector: corrector,
      feedback: feedback,
      settings: settings,
      timings: Self.fastTimings,
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success(text)])
    )
    controller.polish(style: style)
    await fulfillment(of: [finished], timeout: 1.0)
    return corrector.styles
  }
}

private final class TranslateRecordingCorrector: GrammarCorrector, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [CorrectionStyle] = []

  var styles: [CorrectionStyle] {
    lock.withLock { recorded }
  }

  func correct(_ text: String) async throws -> String {
    try await correct(text, style: .minimal)
  }

  func correct(_ text: String, style: CorrectionStyle) async throws -> String {
    lock.withLock { recorded.append(style) }
    return text + "!"
  }
}
