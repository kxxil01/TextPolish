import AppKit
import XCTest

@testable import GrammarCorrection

/// Layout and styling guarantees for the settings window.
final class SettingsWindowLayoutTests: XCTestCase {

  @MainActor
  func testEveryTabFitsWindowWithoutEmptySpace() throws {
    let (controller, viewController) = try makeSettingsWindow()
    let window = try XCTUnwrap(controller.window)
    var heights: [CGFloat] = []

    for index in 0..<4 {
      select(tab: index, in: viewController)
      let section = try XCTUnwrap(viewController.view.subviews.last?.subviews.first)
      let lowestY = try XCTUnwrap(section.subviews.map(\.frame.minY).min())
      XCTAssertEqual(lowestY, 20, accuracy: 0.5, "Tab \(index) should end 20pt above the window bottom")
      XCTAssertEqual(window.contentMinSize, window.contentMaxSize, "Tab \(index) should not be user-resizable")
      heights.append(window.contentRect(forFrameRect: window.frame).height)
    }

    XCTAssertGreaterThan(Set(heights).count, 1, "Window height should follow the selected tab")
  }

  @MainActor
  func testFallbackTitleNamesPartnerProviderAndMissingKey() throws {
    let (_, viewController) = try makeSettingsWindow()

    viewController.providerTileClicked(viewController.anthropicProviderButton)

    XCTAssertEqual(
      viewController.fallbackCheckbox.title,
      "If Anthropic fails, retry with OpenAI (needs an API key for OpenAI)"
    )
  }

  @MainActor
  func testActiveTileWithoutKeyShowsNoKeyBadge() throws {
    let (_, viewController) = try makeSettingsWindow()
    let tile = viewController.geminiProviderButton!
    let badge = try XCTUnwrap(tile.subviews.first { $0.tag == 102 } as? NSTextField)

    XCTAssertEqual(tile.state, .on)
    XCTAssertEqual(badge.stringValue, "", "The check badge means a stored key, not selection")
    XCTAssertEqual(tile.toolTip, "Gemini: No API key")
  }

  @MainActor
  func testExtraInstructionFieldLooksEditable() throws {
    let (_, viewController) = try makeSettingsWindow()

    XCTAssertTrue(viewController.extraInstructionField.isBezeled)
    XCTAssertTrue(viewController.extraInstructionField.isEditable)
    XCTAssertTrue(viewController.extraInstructionField.cell?.wraps ?? false)
  }

  @MainActor
  func testAboutLinksAreClickable() throws {
    let (_, viewController) = try makeSettingsWindow()
    select(tab: 3, in: viewController)
    let section = try XCTUnwrap(viewController.view.subviews.last?.subviews.first)

    let links = section.subviews.compactMap { $0 as? SettingsLinkButton }

    XCTAssertEqual(links.count, 2)
    XCTAssertTrue(links.allSatisfy { $0.action != nil && $0.target != nil })
  }

  @MainActor
  func testHotkeyTextIsVerticallyCentered() {
    let field = KeyComboField(frame: NSRect(x: 0, y: 0, width: 200, height: 26))

    XCTAssertEqual(field.textField.frame.midY, field.bounds.midY, accuracy: 0.5)
  }

  func testCardColorsResolvePerAppearance() throws {
    let light = try XCTUnwrap(NSAppearance(named: .aqua))
    let dark = try XCTUnwrap(NSAppearance(named: .darkAqua))

    XCTAssertNotEqual(
      resolve(SettingsUI.cardFillColor, in: light),
      resolve(SettingsUI.cardFillColor, in: dark),
      "Card fill must differ between light and dark mode"
    )
  }

  // MARK: - Helpers

  @MainActor
  private func makeSettingsWindow() throws -> (SettingsWindowController, SettingsWindowViewController) {
    _ = NSApplication.shared
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let controller = SettingsWindowController(keychainServiceOverride: "com.textpolish.tests.settings-layout")
    let viewController = try XCTUnwrap(controller.viewController)
    return (controller, viewController)
  }

  @MainActor
  private func select(tab index: Int, in viewController: SettingsWindowViewController) {
    viewController.segmentedControl.selectedSegment = index
    viewController.segmentedControl.sendAction(viewController.segmentedControl.action, to: viewController.segmentedControl.target)
  }

  private func resolve(_ color: NSColor, in appearance: NSAppearance) -> NSColor? {
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolved = color.usingColorSpace(.sRGB)
    }
    return resolved
  }
}
