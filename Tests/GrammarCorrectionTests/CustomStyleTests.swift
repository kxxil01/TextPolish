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
      .numbersChanged(["14"])
    )
  }

  func testLogsNameTheStyleWithoutItsInstruction() {
    XCTAssertEqual("\(CorrectionStyle.custom(instruction))", "custom")
    XCTAssertEqual("\(CorrectionStyle.clarify)", "clarify")
  }

  private func status(_ instruction: String?) -> Settings.CustomStyle {
    Settings.CustomStyle(name: "Status", instruction: instruction)
  }

  func testSettingsCarryTheInstructionAndRoundTrip() throws {
    var settings = Settings()
    settings.customStyles["custom"] = status(instruction)
    settings.polishStyle = .custom
    settings.normalizeRuntimeValues()

    XCTAssertEqual(settings.correctionStyle(for: .custom), .custom(instruction))
    XCTAssertEqual(settings.correctionStyle(for: .formal), .formal)
    XCTAssertEqual(settings.displayName(for: .custom), "Status")
    XCTAssertEqual(settings.availablePolishStyles.last, .custom)

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(decoded.customStyle(.custom), status(instruction))
    XCTAssertEqual(decoded.polishStyle, .custom)
  }

  func testThreeCustomStylesEachWithTheirOwnInstruction() {
    var settings = Settings()
    settings.customStyles["custom2"] = Settings.CustomStyle(name: "Client", instruction: "Polite email to a client")
    settings.customStyles["custom3"] = Settings.CustomStyle(name: "Standup", instruction: "Short bullet points")
    settings.normalizeRuntimeValues()

    XCTAssertEqual(settings.availablePolishStyles.suffix(2), [.custom2, .custom3], "Unused slots stay hidden")
    XCTAssertEqual(settings.displayName(for: .custom2), "Client")
    XCTAssertEqual(settings.correctionStyle(for: .custom3), .custom("Short bullet points"))
    XCTAssertEqual(settings.displayName(for: .custom), "Custom", "An unused slot keeps its default name")
  }

  func testOlderSettingsMoveTheirCustomStyleIntoTheFirstSlot() throws {
    let older = Data(#"{"customStyleName":"Status","customStyleInstruction":"Short and direct","polishStyle":"custom"}"#.utf8)

    let settings = try JSONDecoder().decode(Settings.self, from: older)

    XCTAssertEqual(settings.customStyle(.custom), Settings.CustomStyle(name: "Status", instruction: "Short and direct"))
    XCTAssertEqual(settings.polishStyle, .custom)
    let saved = try XCTUnwrap(String(bytes: try JSONEncoder().encode(settings), encoding: .utf8))
    XCTAssertFalse(saved.contains("customStyleInstruction"), "Only the new format is written back")
  }

  func testClearingTheInstructionStopsUsingThatStyleEverywhere() {
    var settings = Settings()
    settings.customStyles["custom"] = status(instruction)
    settings.customStyles["custom2"] = Settings.CustomStyle(name: "Client", instruction: "Polite email")
    settings.polishStyle = .custom
    settings.appPolishStyles = ["com.hnc.Discord": .custom, "com.tinyspeck.slackmacgap": .custom2]
    settings.styleHotKeys = ["custom": Settings.HotKey(keyCode: 14, modifiers: 0)]
    settings.normalizeRuntimeValues()
    XCTAssertEqual(settings.polishStyle, .custom)

    settings.customStyles["custom"] = status("   ")
    settings.normalizeRuntimeValues()

    XCTAssertNil(settings.customStyle(.custom).instruction)
    XCTAssertEqual(settings.polishStyle, .natural)
    XCTAssertEqual(settings.appPolishStyles, ["com.tinyspeck.slackmacgap": .custom2], "Other Custom styles stay")
    XCTAssertTrue(settings.styleHotKeys.isEmpty)
    XCTAssertFalse(settings.availablePolishStyles.contains(.custom))
    XCTAssertEqual(settings.correctionStyle(for: .custom), .clarify)
  }

  func testNameAndInstructionAreTrimmedAndCapped() {
    var settings = Settings()
    settings.customStyles["custom2"] = Settings.CustomStyle(name: "  ", instruction: String(repeating: "a", count: 600))
    settings.normalizeRuntimeValues()

    XCTAssertEqual(settings.customStyle(.custom2).name, "Custom 2")
    XCTAssertEqual(settings.customStyle(.custom2).instruction?.count, 500)
  }

  @MainActor
  func testMenusOfferCustomOnlyOnceItHasAnInstruction() throws {
    let plain = try makeDelegate(Settings())
    XCTAssertEqual(plain.debugVisiblePolishStyleTitles, ["Natural", "Minimal", "Shorter", "Formal", "Friendly"])
    plain.debugShowAppPolishStyles(bundleID: "com.hnc.Discord", name: "Discord")
    XCTAssertFalse(plain.debugAppPolishStyleTitles.contains("Custom"))

    var settings = Settings()
    settings.customStyles["custom"] = status(instruction)
    settings.customStyles["custom3"] = Settings.CustomStyle(name: "Standup", instruction: "Short bullet points")
    let custom = try makeDelegate(settings)
    XCTAssertEqual(Array(custom.debugVisiblePolishStyleTitles.suffix(2)), ["Status", "Standup"])
    custom.debugShowAppPolishStyles(bundleID: "com.hnc.Discord", name: "Discord")
    XCTAssertEqual(custom.debugAppPolishStyleTitles.last, "Standup")
  }

  @MainActor
  func testSettingsEditEachCustomStyleSeparately() throws {
    _ = NSApplication.shared
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let controller = SettingsWindowController(keychainServiceOverride: "com.textpolish.tests.custom-styles")
    let viewController = try XCTUnwrap(controller.viewController)
    viewController.loadSettings()

    viewController.customStyleSlotPopup.selectItem(at: 1)
    viewController.customStyleSlotChanged(viewController.customStyleSlotPopup)
    viewController.customStyleNameField.stringValue = "Client"
    viewController.customStyleInstructionField.stringValue = "Polite email to a client"
    viewController.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: viewController.customStyleInstructionField)
    )

    let saved = Settings.loadOrCreateDefault()
    XCTAssertEqual(saved.customStyle(.custom2), Settings.CustomStyle(name: "Client", instruction: "Polite email to a client"))
    XCTAssertNil(saved.customStyle(.custom).instruction, "The first slot is untouched")
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
