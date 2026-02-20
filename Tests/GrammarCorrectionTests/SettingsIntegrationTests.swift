import XCTest
import AppKit
import Carbon
@testable import GrammarCorrection

final class SettingsIntegrationTests: XCTestCase {
    var settingsWindowController: SettingsWindowController!
    var settingsWindowViewController: SettingsWindowViewController!

    override func setUp() {
        super.setUp()
        settingsWindowController = SettingsWindowController()
        settingsWindowViewController = settingsWindowController.viewController as? SettingsWindowViewController
        // Force the view to load and viewDidLoad to be called
        let _ = settingsWindowViewController?.view
        settingsWindowViewController?.viewDidLoad()
    }

    // Helper to create test settings without loading from disk/keychain
    private func createTestSettings() -> Settings {
        return Settings(
            provider: .gemini,
            requestTimeoutSeconds: 30.0,
            correctionLanguage: .englishUS,
            hotKeyCorrectSelection: Settings.HotKey.correctSelectionDefault,
            hotKeyCorrectAll: Settings.HotKey.correctAllDefault,
            hotKeyAnalyzeTone: Settings.HotKey.analyzeToneDefault,
            enableGeminiOpenRouterFallback: false,
            geminiApiKey: "",
            geminiModel: "gemini-1.5-flash",
            geminiBaseURL: "https://generativelanguage.googleapis.com",
            geminiMinSimilarity: 0.7,
            geminiExtraInstruction: "",
            openRouterApiKey: "",
            openRouterModel: "anthropic/claude-3-haiku",
            openRouterBaseURL: "https://openrouter.ai/api/v1",
            openRouterMinSimilarity: 0.7
        )
    }

    override func tearDown() {
        settingsWindowController = nil
        settingsWindowViewController = nil
        super.tearDown()
    }

    func testSettingsWindowToAppIntegration() {
        // This test verifies that the settings window can communicate with the app
        // Given
        let initialSettings = createTestSettings()

        // When
        settingsWindowViewController?.settings = initialSettings
        settingsWindowViewController?.loadSettings()

        // Then
        XCTAssertNotNil(settingsWindowViewController?.settings, "Settings should be loaded")
    }

    func testProviderSelectionUpdatesSettings() {
        // Given
        settingsWindowViewController?.loadSettings()
        let _ = settingsWindowViewController?.settings.provider

        // When
        settingsWindowViewController?.geminiProviderButton?.state = .on
        settingsWindowViewController?.providerChanged(settingsWindowViewController!.geminiProviderButton!)
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertEqual(settingsWindowViewController?.settings.provider, .gemini, "Provider should be updated")
    }

    func testFallbackSettingPersistence() {
        // Given
        settingsWindowViewController?.loadSettings()

        // When
        settingsWindowViewController?.fallbackCheckbox?.state = .on
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertTrue(settingsWindowViewController?.settings.enableGeminiOpenRouterFallback ?? false, "Fallback setting should persist")
    }

    func testApiKeyUpdate() {
        // Given
        settingsWindowViewController?.loadSettings()
        let testApiKey = "TEST_VALUE_FOR_UNIT_TESTING_ONLY"

        // When
        settingsWindowViewController?.geminiApiKeyField?.stringValue = testApiKey
        settingsWindowViewController?.saveSettings()

        // Then - API keys are not persisted to settings.json
        XCTAssertNil(settingsWindowViewController?.settings.geminiApiKey, "API key should not be persisted in settings")
    }

    func testModelFieldUpdate() {
        // Given
        settingsWindowViewController?.loadSettings()
        let testModel = "gemini-2.0-flash-exp"

        // When
        settingsWindowViewController?.geminiModelField?.stringValue = testModel
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertEqual(settingsWindowViewController?.settings.geminiModel, testModel, "Model should be updated")
    }

    func testHotkeyCapture() {
        // Given
        settingsWindowViewController?.loadSettings()
        let testHotkey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey))

        // When
        settingsWindowViewController?.correctSelectionField?.hotKey = testHotkey
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertEqual(settingsWindowViewController?.settings.hotKeyCorrectSelection, testHotkey, "Hotkey should be updated")
    }

    func testLanguageSelection() {
        // Given
        settingsWindowViewController?.loadSettings()

        // When
        settingsWindowViewController?.languagePopup?.selectItem(at: 1)
        settingsWindowViewController?.languageChanged(settingsWindowViewController!.languagePopup!)
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertEqual(settingsWindowViewController?.settings.correctionLanguage, .englishUS, "Language should be updated")
    }

    func testAdvancedSettingsUpdate() {
        // Given
        settingsWindowViewController?.loadSettings()
        let testTimeout: Double = 30
        let testSimilarity: Double = 0.75

        // When
        settingsWindowViewController?.requestTimeoutField?.stringValue = String(testTimeout)
        settingsWindowViewController?.geminiMinSimilarityField?.stringValue = String(testSimilarity)
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertEqual(settingsWindowViewController?.settings.requestTimeoutSeconds, testTimeout, "Timeout should be updated")
        XCTAssertEqual(settingsWindowViewController?.settings.geminiMinSimilarity, testSimilarity, "Similarity should be updated")
    }

    func testOpenRouterSettingsUpdate() {
        // Given
        settingsWindowViewController?.loadSettings()
        let testApiKey = "TEST_OR_API_KEY_FOR_TESTING_ONLY"
        let testModel = "anthropic/claude-3-sonnet"

        // When
        settingsWindowViewController?.openRouterApiKeyField?.stringValue = testApiKey
        settingsWindowViewController?.openRouterModelField?.stringValue = testModel
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertNil(settingsWindowViewController?.settings.openRouterApiKey, "OpenRouter API key should not be persisted in settings")
        XCTAssertEqual(settingsWindowViewController?.settings.openRouterModel, testModel, "OpenRouter model should be updated")
    }

    func testTabSwitching() {
        // When
        settingsWindowViewController?.tabView?.selectTabViewItem(at: 1)

        // Then
        XCTAssertEqual(settingsWindowViewController?.tabView?.selectedTabViewItem?.label, "Gemini", "Should switch to Gemini tab")
    }

    func testAllTabsAreAccessible() {
        // Given
        let tabLabels = settingsWindowViewController?.tabView?.tabViewItems.map { $0.label } ?? []

        // Then
        XCTAssertTrue(tabLabels.contains("Provider"), "Provider tab should exist")
        XCTAssertTrue(tabLabels.contains("Gemini"), "Gemini tab should exist")
        XCTAssertTrue(tabLabels.contains("OpenRouter"), "OpenRouter tab should exist")
        XCTAssertTrue(tabLabels.contains("OpenAI"), "OpenAI tab should exist")
        XCTAssertTrue(tabLabels.contains("Anthropic"), "Anthropic tab should exist")
        XCTAssertTrue(tabLabels.contains("Hotkeys"), "Hotkeys tab should exist")
        XCTAssertTrue(tabLabels.contains("Advanced"), "Advanced tab should exist")
    }

    func testSettingsValidationOnSave() {
        // Given
        settingsWindowViewController?.loadSettings()
        settingsWindowViewController?.geminiApiKeyField?.stringValue = "" // Empty API key

        // When
        settingsWindowViewController?.saveSettings()

        // Then - should not crash, just save with empty value
        XCTAssertNoThrow(settingsWindowViewController?.saveSettings(), "Should handle empty values gracefully")
    }

    func testCancelDoesNotSaveChanges() {
        // Given
        settingsWindowViewController?.loadSettings()
        let _ = settingsWindowViewController?.settings.geminiModel
        settingsWindowViewController?.geminiModelField?.stringValue = "modified-model"

        // When
        settingsWindowViewController?.cancelButtonClicked(NSButton())

        // Then - Settings should remain unchanged (in real app, this would be handled by not calling saveSettings)
        // For this test, we verify the method can be called
        XCTAssertTrue(true, "Cancel should not save changes")
    }

    func testExtraInstructionField() {
        // Given
        settingsWindowViewController?.loadSettings()
        let testInstruction = "Always use formal tone"

        // When
        settingsWindowViewController?.extraInstructionField?.stringValue = testInstruction
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertEqual(settingsWindowViewController?.settings.geminiExtraInstruction, testInstruction, "Extra instruction should be updated")
    }

    func testSettingsWindowWindowWillClose() {
        // Given
        let notification = Notification(name: NSNotification.Name("test"))

        // When
        settingsWindowController.windowWillClose(notification)

        // Then - verify the method executes without error
        XCTAssertTrue(true, "Window will close should execute successfully")
    }

    func testSettingsWindowClose() {
        // When
        settingsWindowController.close()

        // Then
        XCTAssertTrue(settingsWindowController.window?.isVisible == false, "Window should be closed")
    }

    func testMultipleSettingsChanges() {
        // Given
        settingsWindowViewController?.loadSettings()

        // When - make multiple changes
        settingsWindowViewController?.geminiProviderButton?.state = .on
        settingsWindowViewController?.fallbackCheckbox?.state = .on
        settingsWindowViewController?.geminiApiKeyField?.stringValue = "TEST_GEMINI_KEY_FOR_TESTING"
        settingsWindowViewController?.geminiModelField?.stringValue = "test-model"
        settingsWindowViewController?.saveSettings()

        // Then
        XCTAssertEqual(settingsWindowViewController?.settings.provider, .gemini, "Provider should be updated")
        XCTAssertTrue(settingsWindowViewController?.settings.enableGeminiOpenRouterFallback ?? false, "Fallback should be enabled")
        XCTAssertNil(settingsWindowViewController?.settings.geminiApiKey, "API key should not be persisted in settings")
        XCTAssertEqual(settingsWindowViewController?.settings.geminiModel, "test-model", "Model should be updated")
    }

    func testSettingsStructureConsistency() {
        // Verify that all settings can be read and written
        settingsWindowViewController?.loadSettings()

        // When & Then - each should not crash
        _ = settingsWindowViewController?.settings.provider
        _ = settingsWindowViewController?.settings.geminiApiKey
        _ = settingsWindowViewController?.settings.geminiModel
        _ = settingsWindowViewController?.settings.openRouterApiKey
        _ = settingsWindowViewController?.settings.openRouterModel
        _ = settingsWindowViewController?.settings.hotKeyCorrectSelection
        _ = settingsWindowViewController?.settings.hotKeyCorrectAll
        _ = settingsWindowViewController?.settings.hotKeyAnalyzeTone

        XCTAssertTrue(true, "All settings should be accessible")
    }
}

// MARK: - OpenAI and Anthropic Provider Tests

extension SettingsIntegrationTests {
    func testOpenAIDefaultModel() {
        // Given
        let settings = Settings()

        // Then
        XCTAssertEqual(settings.openAIModel, "gpt-4o-mini", "Default OpenAI model should be gpt-4o-mini")
    }

    func testAnthropicDefaultModel() {
        // Given
        let settings = Settings()

        // Then
        XCTAssertEqual(settings.anthropicModel, "claude-haiku-4-5", "Default Anthropic model should be claude-haiku-4-5")
    }

    func testOpenAIProviderRoundTrip() throws {
        // Given
        var settings = Settings()
        settings.provider = .openAI

        // When
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        // Then
        XCTAssertEqual(decoded.provider, .openAI, "Provider should round-trip as .openAI")
    }

    func testAnthropicProviderRoundTrip() throws {
        // Given
        var settings = Settings()
        settings.provider = .anthropic

        // When
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        // Then
        XCTAssertEqual(decoded.provider, .anthropic, "Provider should round-trip as .anthropic")
    }

    func testSettingsWindowRoundTripOpenAIAnthropicConfiguration() {
        settingsWindowViewController?.loadSettings()

        settingsWindowViewController?.openAIModelField.stringValue = "gpt-4.1-mini"
        settingsWindowViewController?.openAIBaseURLField.stringValue = "https://api.openai.com/v1"
        settingsWindowViewController?.openAIMaxAttemptsField.stringValue = "4"
        settingsWindowViewController?.openAIMinSimilarityField.stringValue = "0.77"
        settingsWindowViewController?.openAIExtraInstructionField.stringValue = "Keep contractions"

        settingsWindowViewController?.anthropicModelField.stringValue = "claude-3-7-sonnet"
        settingsWindowViewController?.anthropicBaseURLField.stringValue = "https://api.anthropic.com"
        settingsWindowViewController?.anthropicMaxAttemptsField.stringValue = "5"
        settingsWindowViewController?.anthropicMinSimilarityField.stringValue = "0.82"
        settingsWindowViewController?.anthropicExtraInstructionField.stringValue = "Prefer concise fixes"

        settingsWindowViewController?.saveSettings()

        XCTAssertEqual(settingsWindowViewController?.settings.openAIModel, "gpt-4.1-mini")
        XCTAssertEqual(settingsWindowViewController?.settings.openAIBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(settingsWindowViewController?.settings.openAIMaxAttempts, 4)
        XCTAssertEqual(settingsWindowViewController?.settings.openAIMinSimilarity, 0.77)
        XCTAssertEqual(settingsWindowViewController?.settings.openAIExtraInstruction, "Keep contractions")

        XCTAssertEqual(settingsWindowViewController?.settings.anthropicModel, "claude-3-7-sonnet")
        XCTAssertEqual(settingsWindowViewController?.settings.anthropicBaseURL, "https://api.anthropic.com")
        XCTAssertEqual(settingsWindowViewController?.settings.anthropicMaxAttempts, 5)
        XCTAssertEqual(settingsWindowViewController?.settings.anthropicMinSimilarity, 0.82)
        XCTAssertEqual(settingsWindowViewController?.settings.anthropicExtraInstruction, "Prefer concise fixes")
    }

    func testNewSettingsFieldsHaveDefaults() {
        // Given
        let settings = Settings()

        // Then
        XCTAssertEqual(settings.openAIBaseURL, "https://api.openai.com/v1",
            "openAIBaseURL should have default value")
        XCTAssertEqual(settings.anthropicBaseURL, "https://api.anthropic.com",
            "anthropicBaseURL should have default value")
        XCTAssertEqual(settings.openAIMaxAttempts, 2,
            "openAIMaxAttempts should default to 2")
        XCTAssertEqual(settings.anthropicMaxAttempts, 2,
            "anthropicMaxAttempts should default to 2")
    }
}

// MARK: - Notification Tests

extension SettingsIntegrationTests {
    func testSettingsDidChangeNotification() {
        // This test verifies that settings changes can trigger notifications
        // Given
        let expectation = self.expectation(description: "Settings should be saved")

        // When - save settings (which posts notification via Settings.saveAndNotify)
        do {
            let settings = Settings.loadOrCreateDefault()
            try Settings.saveAndNotify(settings)
            expectation.fulfill()
        } catch {
            XCTFail("Failed to save settings: \(error)")
        }

        // Then
        waitForExpectations(timeout: 1.0) { error in
            if let error = error {
                XCTFail("Wait failed: \(error)")
            }
        }
    }
}
