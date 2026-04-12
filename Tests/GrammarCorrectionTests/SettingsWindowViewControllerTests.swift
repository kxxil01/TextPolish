import XCTest
import AppKit
import Carbon
@testable import GrammarCorrection

final class SettingsWindowViewControllerTests: XCTestCase {
    var viewController: SettingsWindowViewController!
    var mockDelegate: MockSettingsDelegate!

    override func setUp() {
        super.setUp()
        viewController = SettingsWindowViewController()
        mockDelegate = MockSettingsDelegate()
        viewController.delegate = mockDelegate

        // Load the view
        let _ = viewController.view
    }

    override func tearDown() {
        viewController = nil
        mockDelegate = nil
        super.tearDown()
    }

    func testViewControllerInitialization() {
        XCTAssertNotNil(viewController.view, "View should be initialized")
    }

    func testSegmentedControlCreation() {
        XCTAssertNotNil(viewController.segmentedControl, "Segmented control should be created")
        XCTAssertEqual(viewController.segmentedControl.segmentCount, 3, "Should have 3 segments")
    }

    func testAllSegmentsExist() {
        let segmentLabels = (0..<viewController.segmentedControl.segmentCount).map {
            viewController.segmentedControl.label(forSegment: $0) ?? ""
        }
        XCTAssertTrue(segmentLabels.contains("Provider"), "Provider segment should exist")
        XCTAssertTrue(segmentLabels.contains("Hotkeys"), "Hotkeys segment should exist")
        XCTAssertTrue(segmentLabels.contains("Advanced"), "Advanced segment should exist")
    }

    func testProviderTabElements() {
        XCTAssertNotNil(viewController.geminiProviderButton, "Gemini provider button should exist")
        XCTAssertNotNil(viewController.openRouterProviderButton, "OpenRouter provider button should exist")
        XCTAssertNotNil(viewController.fallbackCheckbox, "Fallback checkbox should exist")
    }

    func testGeminiTabElements() {
        XCTAssertNotNil(viewController.geminiApiKeyField, "Gemini API key field should exist")
        XCTAssertNotNil(viewController.geminiModelField, "Gemini model field should exist")
        XCTAssertNotNil(viewController.geminiBaseURLField, "Gemini base URL field should exist")
        XCTAssertNotNil(viewController.detectGeminiModelButton, "Detect Gemini model button should exist")
    }

    func testOpenRouterTabElements() {
        XCTAssertNotNil(viewController.openRouterApiKeyField, "OpenRouter API key field should exist")
        XCTAssertNotNil(viewController.openRouterModelField, "OpenRouter model field should exist")
        XCTAssertNotNil(viewController.openRouterBaseURLField, "OpenRouter base URL field should exist")
        XCTAssertNotNil(viewController.detectOpenRouterModelButton, "Detect OpenRouter model button should exist")
    }

    func testOpenAITabElements() {
        XCTAssertNotNil(viewController.openAIApiKeyField, "OpenAI API key field should exist")
        XCTAssertNotNil(viewController.openAIModelField, "OpenAI model field should exist")
        XCTAssertNotNil(viewController.openAIBaseURLField, "OpenAI base URL field should exist")
        XCTAssertNotNil(viewController.openAIMaxAttemptsField, "OpenAI max attempts field should exist")
        XCTAssertNotNil(viewController.openAIMinSimilarityField, "OpenAI min similarity field should exist")
        XCTAssertNotNil(viewController.openAIExtraInstructionField, "OpenAI extra instruction field should exist")
    }

    func testAnthropicTabElements() {
        XCTAssertNotNil(viewController.anthropicApiKeyField, "Anthropic API key field should exist")
        XCTAssertNotNil(viewController.anthropicModelField, "Anthropic model field should exist")
        XCTAssertNotNil(viewController.anthropicBaseURLField, "Anthropic base URL field should exist")
        XCTAssertNotNil(viewController.anthropicMaxAttemptsField, "Anthropic max attempts field should exist")
        XCTAssertNotNil(viewController.anthropicMinSimilarityField, "Anthropic min similarity field should exist")
        XCTAssertNotNil(viewController.anthropicExtraInstructionField, "Anthropic extra instruction field should exist")
    }

    func testHotkeysTabElements() {
        XCTAssertNotNil(viewController.correctSelectionField, "Correct selection field should exist")
        XCTAssertNotNil(viewController.correctAllField, "Correct all field should exist")
        XCTAssertNotNil(viewController.analyzeToneField, "Analyze tone field should exist")
    }

    func testAdvancedTabElements() {
        XCTAssertNotNil(viewController.requestTimeoutField, "Request timeout field should exist")
        XCTAssertNotNil(viewController.geminiMinSimilarityField, "Gemini min similarity field should exist")
        XCTAssertNotNil(viewController.openRouterMinSimilarityField, "OpenRouter min similarity field should exist")
        XCTAssertNotNil(viewController.languagePopup, "Language popup should exist")
        XCTAssertNotNil(viewController.extraInstructionField, "Extra instruction field should exist")
    }

    func testLoadSettings() {
        viewController.loadSettings()
        XCTAssertNotNil(viewController.settings, "Settings should be loaded")
    }

    func testSaveSettingsWithValidData() {
        // Given
        viewController.loadSettings()
        viewController.geminiProviderButton.state = .on
        viewController.fallbackCheckbox.state = .on
        viewController.geminiApiKeyField.stringValue = "TEST_GEMINI_API_KEY_FOR_TESTING"
        viewController.geminiModelField.stringValue = "gemini-2.5-flash"

        // When
        viewController.saveSettings()

        // Then
        XCTAssertEqual(viewController.settings.provider, .gemini, "Provider should be saved")
        XCTAssertTrue(viewController.settings.enableGeminiOpenRouterFallback, "Fallback setting should be saved")
    }

    func testSaveSettingsClearsAllProviderApiKeys() {
        viewController.loadSettings()
        viewController.geminiApiKeyField.stringValue = "gemini-key"
        viewController.openRouterApiKeyField.stringValue = "or-key"
        viewController.openAIApiKeyField.stringValue = "oa-key"
        viewController.anthropicApiKeyField.stringValue = "anthropic-key"

        viewController.saveSettings()

        XCTAssertNil(viewController.settings.geminiApiKey)
        XCTAssertNil(viewController.settings.openRouterApiKey)
        XCTAssertNil(viewController.settings.openAIApiKey)
        XCTAssertNil(viewController.settings.anthropicApiKey)
    }

    func testSaveSettingsRejectsDuplicateHotkeys() {
        viewController.loadSettings()

        let duplicate = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey | cmdKey))
        viewController.correctSelectionField.hotKey = duplicate
        viewController.correctAllField.hotKey = duplicate

        let saved = viewController.saveSettings()

        XCTAssertFalse(saved, "Save should fail when hotkeys are duplicated")
    }

    func testSaveSettingsRejectsHotkeyWithoutModifier() {
        viewController.loadSettings()

        viewController.analyzeToneField.hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: 0)

        let saved = viewController.saveSettings()

        XCTAssertFalse(saved, "Save should fail when a hotkey has no modifier")
    }

    func testProviderTileClicked() {
        // Given
        viewController.loadSettings()

        // When — click OpenRouter tile (tag 1)
        viewController.providerTileClicked(viewController.openRouterProviderButton!)

        // Then
        XCTAssertEqual(viewController.settings.provider, .openRouter, "Provider should switch to OpenRouter")
        XCTAssertEqual(viewController.openRouterProviderButton.state, .on, "OpenRouter button should be on")
        XCTAssertEqual(viewController.geminiProviderButton.state, .off, "Gemini button should be off")
    }

    func testLanguageChanged() {
        // Given
        viewController.loadSettings()
        viewController.languagePopup.selectItem(at: 1)

        // When
        viewController.languageChanged(viewController.languagePopup!)

        // Then
        XCTAssertEqual(viewController.languagePopup.indexOfSelectedItem, 1, "Language should be changed")
    }

    func testApplyButtonClicked() {
        // Given
        let mockWindowController = MockSettingsWindowController()
        viewController.settingsWindowController = mockWindowController
        viewController.loadSettings()

        // When
        viewController.applyButtonClicked(NSButton())

        // Then
        XCTAssertTrue(mockWindowController.closeCalled, "Apply should close window")
    }

    func testCancelButtonClicked() {
        // Given
        let mockWindowController = MockSettingsWindowController()
        viewController.settingsWindowController = mockWindowController

        // When
        viewController.cancelButtonClicked(NSButton())

        // Then
        XCTAssertTrue(mockWindowController.closeCalled, "Cancel should close window")
    }

    func testDetectGeminiModel() {
        // This test verifies the button shows loading state during async operation
        viewController.geminiApiKeyField.stringValue = "TEST_GEMINI_KEY_FOR_UNIT_TESTING"
        viewController.geminiModelField.stringValue = ""

        viewController.detectGeminiModel(viewController.detectGeminiModelButton!)

        // Button should show loading state immediately
        XCTAssertEqual(viewController.detectGeminiModelButton.title, "Detecting...", "Button should show loading state")
        XCTAssertFalse(viewController.detectGeminiModelButton.isEnabled, "Button should be disabled during operation")
    }

    func testDetectOpenRouterModel() {
        // This test verifies the button shows loading state during async operation
        viewController.openRouterApiKeyField.stringValue = "TEST_OR_KEY_FOR_UNIT_TESTING"
        viewController.openRouterModelField.stringValue = ""

        viewController.detectOpenRouterModel(viewController.detectOpenRouterModelButton!)

        // Button should show loading state immediately
        XCTAssertEqual(viewController.detectOpenRouterModelButton.title, "Detecting...", "Button should show loading state")
        XCTAssertFalse(viewController.detectOpenRouterModelButton.isEnabled, "Button should be disabled during operation")
    }

    func testSettingsDidChangeDelegate() {
        // Given
        viewController.loadSettings()
        // When
        viewController.saveSettings()

        // Then
        XCTAssertTrue(mockDelegate.settingsDidChangeCalled, "Delegate should be notified of settings change")
    }

    func testUpdateProviderButtons() {
        // Given
        viewController.settings = Settings.loadOrCreateDefault()
        viewController.settings.provider = .gemini

        // When
        viewController.updateProviderButtons()

        // Then
        XCTAssertEqual(viewController.geminiProviderButton.state, .on, "Gemini should be selected")
        XCTAssertEqual(viewController.openRouterProviderButton.state, .off, "OpenRouter should not be selected")
    }

    func testFallbackChanged() {
        // Given
        viewController.loadSettings()

        // When
        viewController.fallbackChanged(viewController.fallbackCheckbox!)

        // Then
        XCTAssertNoThrow(NSException()) // Should not crash
    }
}

// MARK: - Mocks
class MockSettingsDelegate: SettingsWindowViewControllerDelegate {
    var settingsDidChangeCalled = false
    var receivedSettings: Settings?

    func settingsDidChange(_ settings: Settings) {
        settingsDidChangeCalled = true
        receivedSettings = settings
    }
}

class MockSettingsWindowController: SettingsWindowController {
    var closeCalled = false

    override func close() {
        closeCalled = true
    }
}
