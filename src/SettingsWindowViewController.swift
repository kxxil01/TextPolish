import AppKit

protocol SettingsWindowViewControllerDelegate: AnyObject {
    func settingsDidChange(_ settings: Settings)
}

class SettingsWindowViewController: NSViewController {
    var tabView: NSTabView!

    // Provider Tab
    var geminiProviderButton: NSButton!
    var openRouterProviderButton: NSButton!
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
        // Create button bar at bottom with fixed positioning
        let buttonBar = NSView(frame: NSRect(x: 0, y: 0, width: view.bounds.width, height: 50))
        buttonBar.autoresizingMask = [.width, .height]
        view.addSubview(buttonBar)

        // Create Apply button - positioned from right edge
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyButtonClicked(_:)))
        applyButton.frame = NSRect(x: view.bounds.width - 130, y: 10, width: 120, height: 32)
        applyButton.keyEquivalent = "\r"
        applyButton.autoresizingMask = [.minXMargin]  // Keep fixed distance from right edge
        buttonBar.addSubview(applyButton)

        // Create Cancel button - positioned from right edge
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelButtonClicked(_:)))
        cancelButton.frame = NSRect(x: view.bounds.width - 260, y: 10, width: 120, height: 32)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.autoresizingMask = [.minXMargin]  // Keep fixed distance from right edge
        buttonBar.addSubview(cancelButton)

        // Create tab view above button bar
        tabView = NSTabView(frame: NSRect(x: 0, y: 50, width: view.bounds.width, height: view.bounds.height - 50))
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
        // Use full tab view height
        let container = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        var yPosition: CGFloat = container.bounds.height - padding - 30

        // Provider selection label
        let providerLabel = createLabel("Primary Provider", fontSize: 14, weight: .bold)
        providerLabel.frame = NSRect(x: padding, y: yPosition, width: 200, height: 20)
        container.addSubview(providerLabel)
        yPosition -= 40

        // Gemini provider radio button
        geminiProviderButton = NSButton(radioButtonWithTitle: "Gemini (Google)", target: self, action: #selector(providerChanged(_:)))
        geminiProviderButton.frame = NSRect(x: padding * 2, y: yPosition, width: 200, height: 20)
        container.addSubview(geminiProviderButton)
        yPosition -= 30

        // OpenRouter provider radio button
        openRouterProviderButton = NSButton(radioButtonWithTitle: "OpenRouter", target: self, action: #selector(providerChanged(_:)))
        openRouterProviderButton.frame = NSRect(x: padding * 2, y: yPosition, width: 200, height: 20)
        container.addSubview(openRouterProviderButton)
        yPosition -= 50

        // Fallback checkbox
        fallbackCheckbox = NSButton(checkboxWithTitle: "Enable automatic fallback to alternative provider", target: self, action: #selector(fallbackChanged(_:)))
        fallbackCheckbox.frame = NSRect(x: padding, y: yPosition, width: 400, height: 20)
        container.addSubview(fallbackCheckbox)

        return container
    }

    private func createGeminiTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        var yPosition: CGFloat = container.bounds.height - padding - 30

        // API Key
        let apiKeyLabel = createLabel("API Key", fontSize: 12, weight: .medium)
        apiKeyLabel.frame = NSRect(x: padding, y: yPosition, width: 100, height: 17)
        container.addSubview(apiKeyLabel)
        yPosition -= 25

        geminiApiKeyField = NSSecureTextField(frame: NSRect(x: padding, y: yPosition, width: 400, height: 24))
        geminiApiKeyField.placeholderString = "Enter your Gemini API key"
        container.addSubview(geminiApiKeyField)
        yPosition -= 40

        // Model
        let modelLabel = createLabel("Model", fontSize: 12, weight: .medium)
        modelLabel.frame = NSRect(x: padding, y: yPosition, width: 100, height: 17)
        container.addSubview(modelLabel)
        yPosition -= 25

        geminiModelField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 300, height: 24))
        geminiModelField.placeholderString = "gemini-1.5-pro"
        container.addSubview(geminiModelField)

        detectGeminiModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectGeminiModel(_:)))
        detectGeminiModelButton.frame = NSRect(x: padding + 310, y: yPosition, width: 120, height: 24)
        container.addSubview(detectGeminiModelButton)
        yPosition -= 40

        // Base URL
        let baseURLLabel = createLabel("Base URL", fontSize: 12, weight: .medium)
        baseURLLabel.frame = NSRect(x: padding, y: yPosition, width: 100, height: 17)
        container.addSubview(baseURLLabel)
        yPosition -= 25

        geminiBaseURLField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 400, height: 24))
        geminiBaseURLField.placeholderString = "https://generativelanguage.googleapis.com"
        container.addSubview(geminiBaseURLField)

        return container
    }

    private func createOpenRouterTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        var yPosition: CGFloat = container.bounds.height - padding - 30

        // API Key
        let apiKeyLabel = createLabel("API Key", fontSize: 12, weight: .medium)
        apiKeyLabel.frame = NSRect(x: padding, y: yPosition, width: 100, height: 17)
        container.addSubview(apiKeyLabel)
        yPosition -= 25

        openRouterApiKeyField = NSSecureTextField(frame: NSRect(x: padding, y: yPosition, width: 400, height: 24))
        openRouterApiKeyField.placeholderString = "Enter your OpenRouter API key"
        container.addSubview(openRouterApiKeyField)
        yPosition -= 40

        // Model
        let modelLabel = createLabel("Model", fontSize: 12, weight: .medium)
        modelLabel.frame = NSRect(x: padding, y: yPosition, width: 100, height: 17)
        container.addSubview(modelLabel)
        yPosition -= 25

        openRouterModelField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 300, height: 24))
        openRouterModelField.placeholderString = "anthropic/claude-3-haiku"
        container.addSubview(openRouterModelField)

        detectOpenRouterModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectOpenRouterModel(_:)))
        detectOpenRouterModelButton.frame = NSRect(x: padding + 310, y: yPosition, width: 120, height: 24)
        container.addSubview(detectOpenRouterModelButton)
        yPosition -= 40

        // Base URL
        let baseURLLabel = createLabel("Base URL", fontSize: 12, weight: .medium)
        baseURLLabel.frame = NSRect(x: padding, y: yPosition, width: 100, height: 17)
        container.addSubview(baseURLLabel)
        yPosition -= 25

        openRouterBaseURLField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 400, height: 24))
        openRouterBaseURLField.placeholderString = "https://openrouter.ai/api/v1"
        container.addSubview(openRouterBaseURLField)

        return container
    }

    private func createHotkeysTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        var yPosition: CGFloat = container.bounds.height - padding - 30

        // Instructions
        let instructions = createLabel("Click on a field and press your desired key combination", fontSize: 11, weight: .regular)
        instructions.textColor = NSColor.secondaryLabelColor
        instructions.frame = NSRect(x: padding, y: yPosition, width: 400, height: 17)
        container.addSubview(instructions)
        yPosition -= 40

        // Correct Selection
        let selectionLabel = createLabel("Correct Selection", fontSize: 12, weight: .medium)
        selectionLabel.frame = NSRect(x: padding, y: yPosition, width: 150, height: 17)
        container.addSubview(selectionLabel)

        correctSelectionField = KeyComboField(frame: NSRect(x: padding + 160, y: yPosition - 2, width: 200, height: 24))
        container.addSubview(correctSelectionField)
        yPosition -= 40

        // Correct All
        let allLabel = createLabel("Correct All", fontSize: 12, weight: .medium)
        allLabel.frame = NSRect(x: padding, y: yPosition, width: 150, height: 17)
        container.addSubview(allLabel)

        correctAllField = KeyComboField(frame: NSRect(x: padding + 160, y: yPosition - 2, width: 200, height: 24))
        container.addSubview(correctAllField)
        yPosition -= 40

        // Analyze Tone
        let toneLabel = createLabel("Analyze Tone", fontSize: 12, weight: .medium)
        toneLabel.frame = NSRect(x: padding, y: yPosition, width: 150, height: 17)
        container.addSubview(toneLabel)

        analyzeToneField = KeyComboField(frame: NSRect(x: padding + 160, y: yPosition - 2, width: 200, height: 24))
        container.addSubview(analyzeToneField)

        return container
    }

    private func createAdvancedTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        var yPosition: CGFloat = container.bounds.height - padding - 30

        // Request Timeout
        let timeoutLabel = createLabel("Request Timeout (seconds)", fontSize: 12, weight: .medium)
        timeoutLabel.frame = NSRect(x: padding, y: yPosition, width: 200, height: 17)
        container.addSubview(timeoutLabel)
        yPosition -= 25

        requestTimeoutField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 100, height: 24))
        requestTimeoutField.placeholderString = "20"
        container.addSubview(requestTimeoutField)
        yPosition -= 40

        // Gemini Min Similarity
        let geminiSimLabel = createLabel("Gemini Min Similarity", fontSize: 12, weight: .medium)
        geminiSimLabel.frame = NSRect(x: padding, y: yPosition, width: 200, height: 17)
        container.addSubview(geminiSimLabel)
        yPosition -= 25

        geminiMinSimilarityField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 100, height: 24))
        geminiMinSimilarityField.placeholderString = "0.65"
        container.addSubview(geminiMinSimilarityField)
        yPosition -= 40

        // OpenRouter Min Similarity
        let openRouterSimLabel = createLabel("OpenRouter Min Similarity", fontSize: 12, weight: .medium)
        openRouterSimLabel.frame = NSRect(x: padding, y: yPosition, width: 200, height: 17)
        container.addSubview(openRouterSimLabel)
        yPosition -= 25

        openRouterMinSimilarityField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 100, height: 24))
        openRouterMinSimilarityField.placeholderString = "0.65"
        container.addSubview(openRouterMinSimilarityField)
        yPosition -= 40

        // Language
        let languageLabel = createLabel("Correction Language", fontSize: 12, weight: .medium)
        languageLabel.frame = NSRect(x: padding, y: yPosition, width: 200, height: 17)
        container.addSubview(languageLabel)
        yPosition -= 25

        languagePopup = NSPopUpButton(frame: NSRect(x: padding, y: yPosition, width: 200, height: 24))
        languagePopup.addItems(withTitles: ["Auto", "English (US)", "Indonesian"])
        container.addSubview(languagePopup)
        yPosition -= 40

        // Extra Instruction
        let extraLabel = createLabel("Extra Instruction (Optional)", fontSize: 12, weight: .medium)
        extraLabel.frame = NSRect(x: padding, y: yPosition, width: 250, height: 17)
        container.addSubview(extraLabel)
        yPosition -= 25

        extraInstructionField = NSTextField(frame: NSRect(x: padding, y: yPosition, width: 400, height: 80))
        extraInstructionField.placeholderString = "Additional instructions for the AI..."
        extraInstructionField.isEditable = true
        extraInstructionField.isSelectable = true
        extraInstructionField.cell = NSTextFieldCell()
        extraInstructionField.cell!.wraps = true
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
        geminiApiKeyField.stringValue = settings.geminiApiKey ?? ""
        geminiModelField.stringValue = settings.geminiModel
        geminiBaseURLField.stringValue = settings.geminiBaseURL

        // OpenRouter tab
        openRouterApiKeyField.stringValue = settings.openRouterApiKey ?? ""
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
        newSettings.provider = geminiProviderButton.state == .on ? .gemini : .openRouter
        newSettings.fallbackToOpenRouterOnGeminiError = fallbackCheckbox.state == .on

        // Gemini
        newSettings.geminiApiKey = geminiApiKeyField.stringValue.isEmpty ? nil : geminiApiKeyField.stringValue
        newSettings.geminiModel = geminiModelField.stringValue
        newSettings.geminiBaseURL = geminiBaseURLField.stringValue

        // OpenRouter
        newSettings.openRouterApiKey = openRouterApiKeyField.stringValue.isEmpty ? nil : openRouterApiKeyField.stringValue
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
        delegate?.settingsDidChange(settings)
    }

    func updateProviderButtons() {
        let isGemini = settings.provider == .gemini
        geminiProviderButton.state = isGemini ? .on : .off
        openRouterProviderButton.state = isGemini ? .off : .on
    }

    @objc func providerChanged(_ sender: NSButton) {
        if sender == geminiProviderButton {
            geminiProviderButton.state = .on
            openRouterProviderButton.state = .off
        } else {
            geminiProviderButton.state = .off
            openRouterProviderButton.state = .on
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
                    let alert = NSAlert()
                    alert.messageText = "Failed to detect model"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()

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
                    let alert = NSAlert()
                    alert.messageText = "Failed to detect model"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()

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
