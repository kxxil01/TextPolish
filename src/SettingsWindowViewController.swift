import AppKit

protocol SettingsWindowViewControllerDelegate: AnyObject {
    func settingsDidChange(_ settings: Settings)
}

class SettingsWindowViewController: NSViewController {
    var tabView: NSTabView!

    // Provider Tab
    var geminiProviderButton: NSButton!
    var openRouterProviderButton: NSButton!
    var openAIProviderButton: NSButton!
    var anthropicProviderButton: NSButton!
    var fallbackCheckbox: NSButton!

    // Gemini Tab
    var geminiApiKeyField: NSTextField!
    var geminiModelField: NSTextField!
    var geminiBaseURLField: NSTextField!
    var detectGeminiModelButton: NSButton!

    // OpenRouter Tab
    var openRouterApiKeyField: NSTextField!
    var openRouterModelField: NSTextField!
    var openRouterBaseURLField: NSTextField!
    var detectOpenRouterModelButton: NSButton!

    // Hotkeys Tab
    var correctSelectionField: KeyComboField!
    var correctAllField: KeyComboField!
    var analyzeToneField: KeyComboField!

    // Advanced Tab
    var requestTimeoutField: NSTextField!
    var geminiMinSimilarityField: NSTextField!
    var openRouterMinSimilarityField: NSTextField!
    var languagePopup: NSPopUpButton!
    var extraInstructionField: NSTextField!

    var settings: Settings!
    weak var delegate: SettingsWindowViewControllerDelegate?
    weak var settingsWindowController: SettingsWindowController?

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 450))
        rootView.autoresizingMask = [.width, .height]
        self.view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSettings()
    }

    private func setupUI() {
        // Create button bar at bottom
        let buttonBar = NSView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: 50))
        buttonBar.autoresizingMask = [.width, .minYMargin]
        buttonBar.wantsLayer = true
        buttonBar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(buttonBar)

        // Create Apply button
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyButtonClicked(_:)))
        applyButton.frame = NSRect(x: buttonBar.frame.width - 130, y: 10, width: 120, height: 32)
        applyButton.keyEquivalent = "\r"
        applyButton.autoresizingMask = [.minXMargin]
        buttonBar.addSubview(applyButton)

        // Create Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelButtonClicked(_:)))
        cancelButton.frame = NSRect(x: buttonBar.frame.width - 260, y: 10, width: 120, height: 32)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.autoresizingMask = [.minXMargin]
        buttonBar.addSubview(cancelButton)

        // Create tab view above button bar
        let tabHeight = view.frame.height - 50
        tabView = NSTabView(frame: NSRect(x: 0, y: 50, width: view.frame.width, height: tabHeight))
        tabView.autoresizingMask = [.width, .height]
        view.addSubview(tabView)

        // Create Provider tab
        let providerTab = NSTabViewItem(identifier: "Provider")
        providerTab.label = "Provider"
        providerTab.view = createProviderTab()
        tabView.addTabViewItem(providerTab)

        // Create Gemini tab
        let geminiTab = NSTabViewItem(identifier: "Gemini")
        geminiTab.label = "Gemini"
        geminiTab.view = createGeminiTab()
        tabView.addTabViewItem(geminiTab)

        // Create OpenRouter tab
        let openRouterTab = NSTabViewItem(identifier: "OpenRouter")
        openRouterTab.label = "OpenRouter"
        openRouterTab.view = createOpenRouterTab()
        tabView.addTabViewItem(openRouterTab)

        // Create Hotkeys tab
        let hotkeysTab = NSTabViewItem(identifier: "Hotkeys")
        hotkeysTab.label = "Hotkeys"
        hotkeysTab.view = createHotkeysTab()
        tabView.addTabViewItem(hotkeysTab)

        // Create Advanced tab
        let advancedTab = NSTabViewItem(identifier: "Advanced")
        advancedTab.label = "Advanced"
        advancedTab.view = createAdvancedTab()
        tabView.addTabViewItem(advancedTab)

        // Add action handlers
        geminiProviderButton.action = #selector(providerChanged(_:))
        geminiProviderButton.target = self
        openRouterProviderButton.action = #selector(providerChanged(_:))
        openRouterProviderButton.target = self
        openAIProviderButton.action = #selector(providerChanged(_:))
        openAIProviderButton.target = self
        anthropicProviderButton.action = #selector(providerChanged(_:))
        anthropicProviderButton.target = self
        fallbackCheckbox.action = #selector(fallbackChanged(_:))
        fallbackCheckbox.target = self

        detectGeminiModelButton.action = #selector(detectGeminiModel(_:))
        detectGeminiModelButton.target = self
        detectOpenRouterModelButton.action = #selector(detectOpenRouterModel(_:))
        detectOpenRouterModelButton.target = self

        languagePopup.action = #selector(languageChanged(_:))
        languagePopup.target = self
    }

    private func createProviderTab() -> NSView {
        // Use full tab view frame size
        let container = NSView(frame: tabView.frame)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - (padding * 2)

        // Provider selection label
        let providerLabel = createLabel("Primary Provider", fontSize: 16, weight: .bold)
        providerLabel.frame = NSRect(x: padding, y: container.frame.height - 60, width: contentWidth, height: 24)
        providerLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(providerLabel)

        // Gemini provider radio button
        geminiProviderButton = NSButton(radioButtonWithTitle: "Gemini (Google)", target: self, action: #selector(providerChanged(_:)))
        geminiProviderButton.frame = NSRect(x: padding * 2, y: container.frame.height - 100, width: contentWidth, height: 24)
        geminiProviderButton.autoresizingMask = [.width, .minYMargin]
        container.addSubview(geminiProviderButton)

        // OpenRouter provider radio button
        openRouterProviderButton = NSButton(radioButtonWithTitle: "OpenRouter", target: self, action: #selector(providerChanged(_:)))
        openRouterProviderButton.frame = NSRect(x: padding * 2, y: container.frame.height - 130, width: contentWidth, height: 24)
        openRouterProviderButton.autoresizingMask = [.width, .minYMargin]
        container.addSubview(openRouterProviderButton)

        // OpenAI provider radio button
        openAIProviderButton = NSButton(radioButtonWithTitle: "OpenAI", target: self, action: #selector(providerChanged(_:)))
        openAIProviderButton.frame = NSRect(x: padding * 2, y: container.frame.height - 160, width: contentWidth, height: 24)
        openAIProviderButton.autoresizingMask = [.width, .minYMargin]
        container.addSubview(openAIProviderButton)

        // Anthropic provider radio button
        anthropicProviderButton = NSButton(radioButtonWithTitle: "Anthropic", target: self, action: #selector(providerChanged(_:)))
        anthropicProviderButton.frame = NSRect(x: padding * 2, y: container.frame.height - 190, width: contentWidth, height: 24)
        anthropicProviderButton.autoresizingMask = [.width, .minYMargin]
        container.addSubview(anthropicProviderButton)

        // Fallback checkbox
        fallbackCheckbox = NSButton(checkboxWithTitle: "Enable automatic fallback to alternative provider", target: self, action: #selector(fallbackChanged(_:)))
        fallbackCheckbox.frame = NSRect(x: padding, y: container.frame.height - 230, width: contentWidth, height: 24)
        fallbackCheckbox.autoresizingMask = [.width, .minYMargin]
        container.addSubview(fallbackCheckbox)

        return container
    }

    private func createGeminiTab() -> NSView {
        let container = NSView(frame: tabView.frame)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - (padding * 2)

        // API Key
        let apiKeyLabel = createLabel("API Key", fontSize: 12, weight: .medium)
        apiKeyLabel.frame = NSRect(x: padding, y: container.frame.height - 60, width: contentWidth, height: 20)
        apiKeyLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(apiKeyLabel)

        geminiApiKeyField = NSSecureTextField(frame: NSRect(x: padding, y: container.frame.height - 90, width: contentWidth, height: 26))
        geminiApiKeyField.placeholderString = "Enter your Gemini API key"
        geminiApiKeyField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(geminiApiKeyField)

        // Model
        let modelLabel = createLabel("Model", fontSize: 12, weight: .medium)
        modelLabel.frame = NSRect(x: padding, y: container.frame.height - 130, width: contentWidth, height: 20)
        modelLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(modelLabel)

        geminiModelField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 160, width: contentWidth - 130, height: 26))
        geminiModelField.placeholderString = "gemini-1.5-pro"
        geminiModelField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(geminiModelField)

        detectGeminiModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectGeminiModel(_:)))
        detectGeminiModelButton.frame = NSRect(x: container.frame.width - padding - 120, y: container.frame.height - 160, width: 120, height: 26)
        detectGeminiModelButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(detectGeminiModelButton)

        // Base URL
        let baseURLLabel = createLabel("Base URL", fontSize: 12, weight: .medium)
        baseURLLabel.frame = NSRect(x: padding, y: container.frame.height - 200, width: contentWidth, height: 20)
        baseURLLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(baseURLLabel)

        geminiBaseURLField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 230, width: contentWidth, height: 26))
        geminiBaseURLField.placeholderString = "https://generativelanguage.googleapis.com"
        geminiBaseURLField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(geminiBaseURLField)

        return container
    }

    private func createOpenRouterTab() -> NSView {
        let container = NSView(frame: tabView.frame)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - (padding * 2)

        // API Key
        let apiKeyLabel = createLabel("API Key", fontSize: 12, weight: .medium)
        apiKeyLabel.frame = NSRect(x: padding, y: container.frame.height - 60, width: contentWidth, height: 20)
        apiKeyLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(apiKeyLabel)

        openRouterApiKeyField = NSSecureTextField(frame: NSRect(x: padding, y: container.frame.height - 90, width: contentWidth, height: 26))
        openRouterApiKeyField.placeholderString = "Enter your OpenRouter API key"
        openRouterApiKeyField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(openRouterApiKeyField)

        // Model
        let modelLabel = createLabel("Model", fontSize: 12, weight: .medium)
        modelLabel.frame = NSRect(x: padding, y: container.frame.height - 130, width: contentWidth, height: 20)
        modelLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(modelLabel)

        openRouterModelField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 160, width: contentWidth - 130, height: 26))
        openRouterModelField.placeholderString = "anthropic/claude-3-haiku"
        openRouterModelField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(openRouterModelField)

        detectOpenRouterModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectOpenRouterModel(_:)))
        detectOpenRouterModelButton.frame = NSRect(x: container.frame.width - padding - 120, y: container.frame.height - 160, width: 120, height: 26)
        detectOpenRouterModelButton.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(detectOpenRouterModelButton)

        // Base URL
        let baseURLLabel = createLabel("Base URL", fontSize: 12, weight: .medium)
        baseURLLabel.frame = NSRect(x: padding, y: container.frame.height - 200, width: contentWidth, height: 20)
        baseURLLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(baseURLLabel)

        openRouterBaseURLField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 230, width: contentWidth, height: 26))
        openRouterBaseURLField.placeholderString = "https://openrouter.ai/api/v1"
        openRouterBaseURLField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(openRouterBaseURLField)

        return container
    }

    private func createHotkeysTab() -> NSView {
        let container = NSView(frame: tabView.frame)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - (padding * 2)

        // Title
        let titleLabel = createLabel("Hotkey Configuration", fontSize: 16, weight: .bold)
        titleLabel.frame = NSRect(x: padding, y: container.frame.height - 60, width: contentWidth, height: 24)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleLabel)

        // Instruction
        let instructionLabel = createLabel("Click on a field below and press the desired key combination", fontSize: 11, weight: .regular)
        instructionLabel.frame = NSRect(x: padding, y: container.frame.height - 85, width: contentWidth, height: 17)
        instructionLabel.textColor = NSColor.secondaryLabelColor
        instructionLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(instructionLabel)

        // Correct Selection
        let selectionLabel = createLabel("Correct Selection", fontSize: 12, weight: .medium)
        selectionLabel.frame = NSRect(x: padding, y: container.frame.height - 120, width: 200, height: 20)
        selectionLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(selectionLabel)

        correctSelectionField = KeyComboField(frame: NSRect(x: padding + 220, y: container.frame.height - 125, width: 200, height: 30))
        correctSelectionField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(correctSelectionField)

        // Correct All
        let allLabel = createLabel("Correct All", fontSize: 12, weight: .medium)
        allLabel.frame = NSRect(x: padding, y: container.frame.height - 165, width: 200, height: 20)
        allLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(allLabel)

        correctAllField = KeyComboField(frame: NSRect(x: padding + 220, y: container.frame.height - 170, width: 200, height: 30))
        correctAllField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(correctAllField)

        // Analyze Tone
        let toneLabel = createLabel("Analyze Tone", fontSize: 12, weight: .medium)
        toneLabel.frame = NSRect(x: padding, y: container.frame.height - 210, width: 200, height: 20)
        toneLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(toneLabel)

        analyzeToneField = KeyComboField(frame: NSRect(x: padding + 220, y: container.frame.height - 215, width: 200, height: 30))
        analyzeToneField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(analyzeToneField)

        return container
    }

    private func createAdvancedTab() -> NSView {
        let container = NSView(frame: tabView.frame)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - (padding * 2)

        // Request Timeout
        let timeoutLabel = createLabel("Request Timeout (seconds)", fontSize: 12, weight: .medium)
        timeoutLabel.frame = NSRect(x: padding, y: container.frame.height - 60, width: contentWidth, height: 20)
        timeoutLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(timeoutLabel)

        requestTimeoutField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 90, width: 150, height: 26))
        requestTimeoutField.placeholderString = "20"
        requestTimeoutField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(requestTimeoutField)

        // Gemini Min Similarity
        let geminiSimLabel = createLabel("Gemini Min Similarity", fontSize: 12, weight: .medium)
        geminiSimLabel.frame = NSRect(x: padding, y: container.frame.height - 130, width: contentWidth, height: 20)
        geminiSimLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(geminiSimLabel)

        geminiMinSimilarityField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 160, width: 150, height: 26))
        geminiMinSimilarityField.placeholderString = "0.65"
        geminiMinSimilarityField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(geminiMinSimilarityField)

        // OpenRouter Min Similarity
        let openRouterSimLabel = createLabel("OpenRouter Min Similarity", fontSize: 12, weight: .medium)
        openRouterSimLabel.frame = NSRect(x: padding, y: container.frame.height - 200, width: contentWidth, height: 20)
        openRouterSimLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(openRouterSimLabel)

        openRouterMinSimilarityField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 230, width: 150, height: 26))
        openRouterMinSimilarityField.placeholderString = "0.65"
        openRouterMinSimilarityField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(openRouterMinSimilarityField)

        // Language
        let languageLabel = createLabel("Correction Language", fontSize: 12, weight: .medium)
        languageLabel.frame = NSRect(x: padding, y: container.frame.height - 270, width: contentWidth, height: 20)
        languageLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(languageLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: padding, y: container.frame.height - 300, width: 200, height: 26))
        languagePopup.addItems(withTitles: ["Auto", "English (US)", "Indonesian"])
        languagePopup.autoresizingMask = [.width, .minYMargin]
        container.addSubview(languagePopup)

        // Extra Instruction
        let extraLabel = createLabel("Extra Instruction (Optional)", fontSize: 12, weight: .medium)
        extraLabel.frame = NSRect(x: padding, y: container.frame.height - 340, width: contentWidth, height: 20)
        extraLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(extraLabel)

        extraInstructionField = NSTextField(frame: NSRect(x: padding, y: container.frame.height - 420, width: contentWidth, height: 70))
        extraInstructionField.placeholderString = "Additional instructions for the AI..."
        extraInstructionField.isEditable = true
        extraInstructionField.isSelectable = true
        extraInstructionField.cell = NSTextFieldCell()
        extraInstructionField.cell!.wraps = true
        extraInstructionField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(extraInstructionField)

        return container
    }

    private func createLabel(_ text: String, fontSize: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return label
    }

    func loadSettings() {
        settings = Settings.loadOrCreateDefault()

        // Provider tab
        updateProviderButtons()
        fallbackCheckbox.state = settings.fallbackToOpenRouterOnGeminiError ? .on : .off

        // Gemini tab
        geminiApiKeyField.stringValue = ""
        geminiModelField.stringValue = settings.geminiModel
        geminiBaseURLField.stringValue = settings.geminiBaseURL

        // OpenRouter tab
        openRouterApiKeyField.stringValue = ""
        openRouterModelField.stringValue = settings.openRouterModel
        openRouterBaseURLField.stringValue = settings.openRouterBaseURL

        // Hotkeys
        correctSelectionField.loadFromHotKey(settings.hotKeyCorrectSelection)
        correctAllField.loadFromHotKey(settings.hotKeyCorrectAll)
        analyzeToneField.loadFromHotKey(settings.hotKeyAnalyzeTone)

        // Advanced
        requestTimeoutField.stringValue = String(format: "%.0f", settings.requestTimeoutSeconds)
        geminiMinSimilarityField.stringValue = String(format: "%.2f", settings.geminiMinSimilarity)
        openRouterMinSimilarityField.stringValue = String(format: "%.2f", settings.openRouterMinSimilarity)

        // Language
        switch settings.correctionLanguage {
        case .auto:
            languagePopup.selectItem(at: 0)
        case .englishUS:
            languagePopup.selectItem(at: 1)
        case .indonesian:
            languagePopup.selectItem(at: 2)
        }

        extraInstructionField.stringValue = settings.geminiExtraInstruction ?? ""
    }

    @objc func applyButtonClicked(_ sender: NSButton) {
        saveSettings()
        settingsWindowController?.close()
    }

    @objc func cancelButtonClicked(_ sender: NSButton) {
        settingsWindowController?.close()
    }

    @objc func languageChanged(_ sender: NSPopUpButton) {
        // Language selection changed
    }

    func saveSettings() {
        guard var newSettings = settings else { return }

        // Provider
        if geminiProviderButton.state == .on {
            newSettings.provider = .gemini
        } else if openRouterProviderButton.state == .on {
            newSettings.provider = .openRouter
        } else if openAIProviderButton.state == .on {
            newSettings.provider = .openAI
        } else if anthropicProviderButton.state == .on {
            newSettings.provider = .anthropic
        }
        newSettings.fallbackToOpenRouterOnGeminiError = fallbackCheckbox.state == .on

        // Gemini
        // API keys are managed via Keychain and should not be persisted in settings.json.
        newSettings.geminiApiKey = nil
        newSettings.geminiModel = geminiModelField.stringValue
        newSettings.geminiBaseURL = geminiBaseURLField.stringValue

        // OpenRouter
        newSettings.openRouterApiKey = nil
        newSettings.openRouterModel = openRouterModelField.stringValue
        newSettings.openRouterBaseURL = openRouterBaseURLField.stringValue

        // Hotkeys
        if let selectionHotKey = correctSelectionField.hotKey {
            newSettings.hotKeyCorrectSelection = selectionHotKey
        }
        if let allHotKey = correctAllField.hotKey {
            newSettings.hotKeyCorrectAll = allHotKey
        }
        if let toneHotKey = analyzeToneField.hotKey {
            newSettings.hotKeyAnalyzeTone = toneHotKey
        }

        // Advanced
        newSettings.requestTimeoutSeconds = Double(requestTimeoutField.stringValue) ?? 20
        newSettings.geminiMinSimilarity = Double(geminiMinSimilarityField.stringValue) ?? 0.65
        newSettings.openRouterMinSimilarity = Double(openRouterMinSimilarityField.stringValue) ?? 0.65

        // Language
        switch languagePopup.indexOfSelectedItem {
        case 0:
            newSettings.correctionLanguage = .auto
        case 1:
            newSettings.correctionLanguage = .englishUS
        case 2:
            newSettings.correctionLanguage = .indonesian
        default:
            break
        }

        newSettings.geminiExtraInstruction = extraInstructionField.stringValue.isEmpty ? nil : extraInstructionField.stringValue

        settings = newSettings
        do {
            try Settings.saveAndNotify(newSettings)
        } catch {
            NSLog("[TextPolish] Failed to save settings from Settings window: \(error)")
        }
        delegate?.settingsDidChange(settings)
    }

    func updateProviderButtons() {
        let provider = settings.provider
        geminiProviderButton.state = provider == .gemini ? .on : .off
        openRouterProviderButton.state = provider == .openRouter ? .on : .off
        openAIProviderButton.state = provider == .openAI ? .on : .off
        anthropicProviderButton.state = provider == .anthropic ? .on : .off
    }

    @objc func providerChanged(_ sender: NSButton) {
        geminiProviderButton.state = .off
        openRouterProviderButton.state = .off
        openAIProviderButton.state = .off
        anthropicProviderButton.state = .off

        if sender == geminiProviderButton {
            geminiProviderButton.state = .on
        } else if sender == openRouterProviderButton {
            openRouterProviderButton.state = .on
        } else if sender == openAIProviderButton {
            openAIProviderButton.state = .on
        } else if sender == anthropicProviderButton {
            anthropicProviderButton.state = .on
        }
    }

    @objc func fallbackChanged(_ sender: NSButton) {
        // Toggle fallback setting
    }

    @objc func detectGeminiModel(_ sender: NSButton) {
        detectGeminiModelButton.isEnabled = false
        detectGeminiModelButton.title = "Detecting..."

        Task {
            do {
                let detectedModel = try await ModelDetector.detectGeminiModel(
                    apiKey: geminiApiKeyField.stringValue,
                    baseURL: geminiBaseURLField.stringValue
                )

                await MainActor.run {
                    geminiModelField.stringValue = detectedModel
                    detectGeminiModelButton.title = "Detect Model"
                    detectGeminiModelButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    // Don't show alert in test environment to avoid blocking CI/CD
                    #if DEBUG
                    if NSClassFromString("XCTestCase") != nil {
                        NSLog("[TextPolish] Gemini model detection error suppressed in test environment: \(error)")
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Failed to detect model"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                    #endif

                    detectGeminiModelButton.title = "Detect Model"
                    detectGeminiModelButton.isEnabled = true
                }
            }
        }
    }

    @objc func detectOpenRouterModel(_ sender: NSButton) {
        detectOpenRouterModelButton.isEnabled = false
        detectOpenRouterModelButton.title = "Detecting..."

        Task {
            do {
                let detectedModel = try await ModelDetector.detectOpenRouterModel(
                    apiKey: openRouterApiKeyField.stringValue
                )

                await MainActor.run {
                    openRouterModelField.stringValue = detectedModel
                    detectOpenRouterModelButton.title = "Detect Model"
                    detectOpenRouterModelButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    // Don't show alert in test environment to avoid blocking CI/CD
                    #if DEBUG
                    if NSClassFromString("XCTestCase") != nil {
                        NSLog("[TextPolish] OpenRouter model detection error suppressed in test environment: \(error)")
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Failed to detect model"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                    #endif

                    detectOpenRouterModelButton.title = "Detect Model"
                    detectOpenRouterModelButton.isEnabled = true
                }
            }
        }
    }
}

extension SettingsWindowViewController: NSTabViewDelegate {
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        // Handle tab selection if needed
    }
}
