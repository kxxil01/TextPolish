import AppKit
import XCTest

@testable import GrammarCorrection

/// Custom: a style the writer describes in their own words, offered once it has an instruction.
final class CustomStyleTests: XCTestCase {
  private let instruction = "Short and direct, as a status update to my manager"

  private func prompt(_ style: CorrectionStyle, retryReason: CorrectionRetryReason? = nil) -> String {
    CorrectionPromptBuilder.makePrompt(
      text: "hello", retryReason: retryReason, correctionLanguage: .auto, extraInstruction: nil, style: style
    ).system
  }

  func testPromptFollowsTheWritersStyleAndKeepsTheMeaningGuards() {
    let system = prompt(.custom(instruction))

    XCTAssertTrue(system.contains("Writer's style: \(instruction)"))
    XCTAssertTrue(system.contains("never change what the text says"))
    XCTAssertTrue(system.contains("Keep the meaning exactly"))
    XCTAssertTrue(system.contains("Do not translate"))
    XCTAssertTrue(system.contains("unless the writer's style asks for another layout"))
    XCTAssertFalse(system.contains("Example output:"), "examples would pull toward a built-in style")
    XCTAssertTrue(prompt(.custom(instruction), retryReason: .overRewrite).contains("only rephrase the parts"))
  }

  func testCustomStyleMayChangeTheLayoutButKeepsNumbersAndSimilarityFloor() {
    struct Checker: TextProcessor { let minSimilarity = 0.65 }
    let checker = Checker()
    let style = CorrectionStyle.custom(instruction)
    let original = "Finished the report and the deck, sent both to Sam on 14 March."
    let bullets = "- Finished the report and the deck\n- Sent both to Sam on 14 March"

    XCTAssertTrue(checker.keepsLineStructure(original: original, candidate: bullets, style: style))
    XCTAssertEqual(style.minimumSimilarity(configured: 0.65), 0.3)
    XCTAssertTrue(style.rewritesWording)
    let wrongDate = bullets.replacingOccurrences(of: "14", with: "15")
    XCTAssertEqual(
      checker.rejectionReason(original: original, candidate: wrongDate, style: style, minimumSimilarity: 0.3),
      .numbersChanged
    )
  }

  func testLogsNameTheStyleWithoutItsInstruction() {
    XCTAssertEqual("\(CorrectionStyle.custom(instruction))", "custom")
    XCTAssertEqual("\(CorrectionStyle.clarify)", "clarify")
  }

  func testSettingsCarryTheInstructionAndRoundTrip() throws {
    var settings = Settings()
    settings.customStyleName = "Status"
    settings.customStyleInstruction = instruction
    settings.polishStyle = .custom
    settings.normalizeRuntimeValues()

    XCTAssertEqual(settings.correctionStyle(for: .custom), .custom(instruction))
    XCTAssertEqual(settings.correctionStyle(for: .formal), .formal)
    XCTAssertEqual(settings.displayName(for: .custom), "Status")
    XCTAssertEqual(settings.availablePolishStyles.last, .custom)

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(decoded.customStyleName, "Status")
    XCTAssertEqual(decoded.customStyleInstruction, instruction)
    XCTAssertEqual(decoded.polishStyle, .custom)
  }

  func testClearingTheInstructionStopsUsingCustomEverywhere() {
    var settings = Settings()
    settings.customStyleInstruction = instruction
    settings.polishStyle = .custom
    settings.appPolishStyles = ["com.hnc.Discord": .custom, "com.tinyspeck.slackmacgap": .formal]
    settings.styleHotKeys = ["custom": Settings.HotKey(keyCode: 14, modifiers: 0)]
    settings.normalizeRuntimeValues()
    XCTAssertEqual(settings.polishStyle, .custom)

    settings.customStyleInstruction = "   "
    settings.normalizeRuntimeValues()

    XCTAssertNil(settings.customStyleInstruction)
    XCTAssertEqual(settings.polishStyle, .natural)
    XCTAssertEqual(settings.appPolishStyles, ["com.tinyspeck.slackmacgap": .formal])
    XCTAssertTrue(settings.styleHotKeys.isEmpty)
    XCTAssertFalse(settings.availablePolishStyles.contains(.custom))
    XCTAssertEqual(settings.correctionStyle(for: .custom), .clarify)
  }

  func testNameAndInstructionAreTrimmedAndCapped() {
    var settings = Settings()
    settings.customStyleName = "  "
    settings.customStyleInstruction = String(repeating: "a", count: 600)
    settings.normalizeRuntimeValues()

    XCTAssertEqual(settings.customStyleName, "Custom")
    XCTAssertEqual(settings.customStyleInstruction?.count, 500)
  }

  @MainActor
  func testMenusOfferCustomOnlyOnceItHasAnInstruction() throws {
    let plain = try makeDelegate(Settings())
    XCTAssertEqual(plain.debugVisiblePolishStyleTitles, ["Natural", "Minimal", "Shorter", "Formal", "Friendly"])
    plain.debugShowAppPolishStyles(bundleID: "com.hnc.Discord", name: "Discord")
    XCTAssertFalse(plain.debugAppPolishStyleTitles.contains("Custom"))

    var settings = Settings()
    settings.customStyleName = "Status"
    settings.customStyleInstruction = instruction
    let custom = try makeDelegate(settings)
    XCTAssertEqual(custom.debugVisiblePolishStyleTitles.last, "Status")
    custom.debugShowAppPolishStyles(bundleID: "com.hnc.Discord", name: "Discord")
    XCTAssertEqual(custom.debugAppPolishStyleTitles.last, "Status")
  }

  @MainActor
  private func makeDelegate(_ settings: Settings) throws -> AppDelegate {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    try Settings.save(settings)
    addTeardownBlock { try? Settings.save(Settings()) }
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()
    return delegate
  }
}
