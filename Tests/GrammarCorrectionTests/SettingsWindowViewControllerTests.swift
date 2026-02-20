import XCTest
import AppKit
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

    func testTabViewCreation() {
        XCTAssertNotNil(viewController.tabView, "Tab view should be created")
        XCTAssertEqual(viewController.tabView?.tabViewItems.count, 7, "Should have 7 tabs")
    }

    func testAllTabsCreated() {
        let tabLabels = viewController.tabView?.tabViewItems.map { $0.label } ?? []
        XCTAssertTrue(tabLabels.contains("Provider"), "Provider tab should exist")
        XCTAssertTrue(tabLabels.contains("Gemini"), "Gemini tab should exist")
        XCTAssertTrue(tabLabels.contains("OpenRouter"), "OpenRouter tab should exist")
        XCTAssertTrue(tabLabels.contains("OpenAI"), "OpenAI tab should exist")
        XCTAssertTrue(tabLabels.contains("Anthropic"), "Anthropic tab should exist")
        XCTAssertTrue(tabLabels.contains("Hotkeys"), "Hotkeys tab should exist")
        XCTAssertTrue(tabLabels.contains("Advanced"), "Advanced tab should exist")
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
        viewController.geminiModelField.stringValue = "gemini-1.5-pro"

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

    func testProviderChanged() {
        // Given
        viewController.loadSettings()
        viewController.openRouterProviderButton.state = .on

        // When
        viewController.providerChanged(viewController.geminiProviderButton!)

        // Then
        XCTAssertEqual(viewController.geminiProviderButton.state, .on, "Gemini button should be on")
        XCTAssertEqual(viewController.openRouterProviderButton.state, .off, "OpenRouter button should be off")
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
        let initialSettings = viewController.settings

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
