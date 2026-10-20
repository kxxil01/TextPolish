import AppKit
import Carbon
import XCTest

@testable import GrammarCorrection

/// Edge cases in how the settings window commits edits and records hotkeys.
final class SettingsWindowEditingTests: XCTestCase {

  @MainActor
  func testSwitchingProviderCommitsInProgressModelEdit() throws {
    let (_, viewController, window) = try makeSettingsWindow()
    let modelField = try XCTUnwrap(viewController.view.findTextField(placeholder: "gemini-2.5-flash"))
    XCTAssertTrue(window.makeFirstResponder(modelField))
    modelField.currentEditor()?.string = "my-custom-gemini"

    viewController.providerTileClicked(viewController.openRouterProviderButton)

    let saved = Settings.loadOrCreateDefault()
    XCTAssertEqual(saved.geminiModel, "my-custom-gemini", "Edit belongs to the provider it was typed for")
    XCTAssertEqual(saved.openRouterModel, Settings().openRouterModel, "New provider must not receive the edit")
    XCTAssertEqual(saved.provider, .openRouter)
  }

  @MainActor
  func testClosingWindowCommitsInProgressModelEdit() throws {
    let (controller, viewController, window) = try makeSettingsWindow()
    let modelField = try XCTUnwrap(viewController.view.findTextField(placeholder: "gemini-2.5-flash"))
    XCTAssertTrue(window.makeFirstResponder(modelField))
    modelField.currentEditor()?.string = "closing-model"

    controller.close()

    XCTAssertEqual(Settings.loadOrCreateDefault().geminiModel, "closing-model")
  }

  @MainActor
  func testRejectedHotkeyRevertsFieldToSavedValue() throws {
    let (_, viewController, _) = try makeSettingsWindow()
    let saved = Settings.loadOrCreateDefault()

    viewController.correctAllField.hotKey = saved.hotKeyCorrectSelection

    XCTAssertEqual(viewController.correctAllField.hotKey, saved.hotKeyCorrectAll)
    XCTAssertEqual(viewController.correctAllField.textField.stringValue, saved.hotKeyCorrectAll.displayString)
    XCTAssertEqual(Settings.loadOrCreateDefault().hotKeyCorrectAll, saved.hotKeyCorrectAll)
  }

  @MainActor
  func testRewriteHotkeyFieldSavesLive() throws {
    let (_, viewController, _) = try makeSettingsWindow()
    let custom = Settings.HotKey(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(controlKey | optionKey | cmdKey))

    viewController.rewriteSelectionField.hotKey = custom

    XCTAssertEqual(Settings.loadOrCreateDefault().hotKeyRewriteSelection, custom)
  }

  @MainActor
  func testRewriteHotkeyMatchingAnotherActionIsRejected() throws {
    let (_, viewController, _) = try makeSettingsWindow()
    let saved = Settings.loadOrCreateDefault()

    viewController.rewriteSelectionField.hotKey = saved.hotKeyAnalyzeTone

    XCTAssertEqual(viewController.rewriteSelectionField.hotKey, saved.hotKeyRewriteSelection)
    XCTAssertEqual(Settings.loadOrCreateDefault().hotKeyRewriteSelection, saved.hotKeyRewriteSelection)
  }

  @MainActor
  func testDetectWithoutApiKeyDoesNotStartDetection() throws {
    let (_, viewController, _) = try makeSettingsWindow()

    viewController.detectGeminiModel(viewController.detectGeminiModelButton)

    XCTAssertTrue(viewController.detectGeminiModelButton.isEnabled)
    XCTAssertEqual(viewController.detectGeminiModelButton.title, "Detect Model")
  }

  @MainActor
  func testStartingRecordingStopsOtherHotkeyField() {
    let window = NSWindow()
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
    window.contentView = container
    let first = KeyComboField(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
    let second = KeyComboField(frame: NSRect(x: 200, y: 0, width: 200, height: 30))
    container.addSubview(first)
    container.addSubview(second)

    triggerRecordingClick(on: first)
    triggerRecordingClick(on: second)

    XCTAssertFalse(first.hasActiveKeyDownMonitor, "Only one field may record at a time")
    XCTAssertTrue(second.hasActiveKeyDownMonitor)
    triggerRecordingClick(on: second)
  }

  @MainActor
  func testRemovingRecordingFieldFromWindowStopsRecording() {
    let window = NSWindow()
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
    window.contentView = container
    let field = KeyComboField(frame: container.bounds)
    container.addSubview(field)

    triggerRecordingClick(on: field)
    field.removeFromSuperview()

    XCTAssertFalse(field.hasActiveKeyDownMonitor, "A detached field must not keep a key monitor")
  }

  // MARK: - Helpers

  @MainActor
  private func makeSettingsWindow() throws -> (SettingsWindowController, SettingsWindowViewController, NSWindow) {
    _ = NSApplication.shared
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let controller = SettingsWindowController(keychainServiceOverride: "com.textpolish.tests.settings-editing")
    let window = try XCTUnwrap(controller.window)
    let viewController = try XCTUnwrap(controller.viewController)
    return (controller, viewController, window)
  }

  private func triggerRecordingClick(on field: KeyComboField) {
    _ = field.perform(NSSelectorFromString("handleClick:"), with: NSClickGestureRecognizer())
  }
}

private extension NSView {
  func findTextField(placeholder: String) -> NSTextField? {
    if let field = self as? NSTextField, field.placeholderString == placeholder {
      return field
    }
    for subview in subviews {
      if let found = subview.findTextField(placeholder: placeholder) {
        return found
      }
    }
    return nil
  }
}
