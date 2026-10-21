import AppKit
import XCTest

@testable import GrammarCorrection

/// Translate to English: natural English from another language, with the same meaning checks as Polish.
final class TranslateTests: XCTestCase {
  private func prompt(language: Settings.CorrectionLanguage = .auto) -> String {
    CorrectionPromptBuilder.makePrompt(
      text: "tolong cek ya", retryReason: nil, correctionLanguage: language, extraInstruction: nil, style: .translateToEnglish
    ).system
  }

  func testPromptTranslatesToNaturalEnglishAndKeepsTheMeaning() {
    let system = prompt()

    XCTAssertTrue(system.contains("Translate the text into clear, natural English"))
    XCTAssertTrue(system.contains("Keep the meaning exactly"))
    XCTAssertTrue(system.contains("If part of the text is already in English, keep it"))
    XCTAssertTrue(system.contains("Example output: please check the report I sent yesterday"))
    XCTAssertTrue(system.contains("Return only the English text."))
    XCTAssertTrue(system.contains("⟦GC_PROTECT_XXXX_0⟧"), "Never Change words and code stay protected")
    XCTAssertTrue(system.contains("Join line breaks that split one paragraph"))
    XCTAssertFalse(system.contains("Do not translate"))
  }

  func testCorrectionLanguageDoesNotStopTheTranslation() {
    XCTAssertFalse(prompt(language: .indonesian).contains("Correct in Indonesian"))
    XCTAssertFalse(prompt(language: .englishUS).contains("Do not translate"))
  }

  func testTranslationSkipsTheSimilarityFloorButKeepsNumbersAndLayout() {
    struct Checker: TextProcessor { let minSimilarity = 0.65 }
    let checker = Checker()
    let original = "Tolong transfer Rp 2.500.000 sebelum 14 Maret.\n\n- invoice\n- kwitansi"
    let english = "Please transfer Rp 2.500.000 before 14 March.\n\n- invoice\n- receipt"

    XCTAssertEqual(CorrectionStyle.translateToEnglish.minimumSimilarity(configured: 0.65), 0)
    XCTAssertNil(checker.rejectionReason(original: original, candidate: english, style: .translateToEnglish, minimumSimilarity: 0))
    XCTAssertEqual(
      checker.rejectionReason(
        original: original, candidate: english.replacingOccurrences(of: "2.500.000", with: "2,500,000"),
        style: .translateToEnglish, minimumSimilarity: 0
      ),
      .numbersChanged(["2.500.000"])
    )
    XCTAssertEqual(
      checker.rejectionReason(
        original: original, candidate: english.replacingOccurrences(of: "\n\n", with: " "),
        style: .translateToEnglish, minimumSimilarity: 0
      ),
      .lineStructureChanged
    )
    XCTAssertEqual("\(CorrectionStyle.translateToEnglish)", "translate")
  }

  func testShortcutDefaultsToControlOptionCommandEAndRoundTrips() throws {
    let older = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
    XCTAssertEqual(older.hotKeyTranslate, .translateDefault)
    XCTAssertEqual(Settings.HotKey.translateDefault.displayString, "⌃⌥⌘E")

    var settings = Settings()
    settings.hotKeyTranslate = Settings.HotKey(keyCode: 17, modifiers: Settings.HotKey.translateDefault.modifiers)
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(decoded.hotKeyTranslate, settings.hotKeyTranslate)
  }

  @MainActor
  func testShortcutIsRegisteredAsAnExtraAndHandled() {
    let delegate = AppDelegate()
    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.translate.rawValue, now: .now))
  }
}

extension CorrectionControllerTests {
  @MainActor
  func testTranslateSendsItsStyleAndRecordsItForUndo() async {
    let finished = expectation(description: "translate finished")
    var records: [PolishRecord] = []
    let corrector = StyleRecordingCorrector()
    let controller = CorrectionController(
      corrector: corrector,
      feedback: StubFeedback(),
      settings: Settings(),
      timings: Self.fastTimings,
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success("tolong cek ya")]),
      frontmostApplicationPIDProvider: { 4242 },
      onPolished: { record in
        records.append(record)
        finished.fulfill()
      }
    )

    controller.polish(style: .translateToEnglish)

    await fulfillment(of: [finished], timeout: 1.0)
    XCTAssertEqual(corrector.styles, [.translateToEnglish])
    XCTAssertEqual(records.first?.style, .translateToEnglish)
    XCTAssertEqual(records.first?.polished, "please check")
  }
}

private final class StyleRecordingCorrector: GrammarCorrector, @unchecked Sendable {
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
    return "please check"
  }
}
