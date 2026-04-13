import AppKit

protocol SettingsWindowViewControllerDelegate: AnyObject {
    func settingsDidChange(_ settings: Settings)
}

class SettingsWindowViewController: NSViewController, NSTextFieldDelegate {
    // MARK: - Segment Control

    var segmentedControl: NSSegmentedControl!
    private var contentContainer: NSView!

    // MARK: - Provider Fields

    var geminiProviderButton: NSButton!
    var openRouterProviderButton: NSButton!
    var openAIProviderButton: NSButton!
    var anthropicProviderButton: NSButton!
    var fallbackCheckbox: NSButton!

    // Shared detail fields for the visible provider panel
    private var providerApiKeyField: NSTextField!
    private var providerModelField: NSTextField!
    private var providerBaseURLField: NSTextField!
    private var detectModelButton: NSButton!

    // Per-provider backing fields (always created, tests read/write these)
    var geminiApiKeyField: NSTextField!
    var geminiModelField: NSTextField!
    var geminiBaseURLField: NSTextField!
    var detectGeminiModelButton: NSButton!

    var openRouterApiKeyField: NSTextField!
    var openRouterModelField: NSTextField!
    var openRouterBaseURLField: NSTextField!
    var detectOpenRouterModelButton: NSButton!

    var openAIApiKeyField: NSTextField!
    var openAIModelField: NSTextField!
    var openAIBaseURLField: NSTextField!
    var openAIMaxAttemptsField: NSTextField!
    var openAIMinSimilarityField: NSTextField!
    var openAIExtraInstructionField: NSTextField!

    var anthropicApiKeyField: NSTextField!
    var anthropicModelField: NSTextField!
    var anthropicBaseURLField: NSTextField!
    var anthropicMaxAttemptsField: NSTextField!
    var anthropicMinSimilarityField: NSTextField!
    var anthropicExtraInstructionField: NSTextField!

    // MARK: - Hotkey Fields

    var correctSelectionField: KeyComboField!
    var correctAllField: KeyComboField!
    var analyzeToneField: KeyComboField!

    // MARK: - Advanced Fields

    var requestTimeoutField: NSTextField!
    var languagePopup: NSPopUpButton!
    var extraInstructionField: NSTextField!
    var geminiMinSimilarityField: NSTextField!
    var openRouterMinSimilarityField: NSTextField!

    // MARK: - Per-provider Advanced Fields (promoted from local vars — issue #5)

    var activeSimField: NSTextField!
    var activeAttField: NSTextField!

    // MARK: - State

    var settings: Settings!
    weak var delegate: SettingsWindowViewControllerDelegate?
    weak var settingsWindowController: SettingsWindowController?
    private var settingsObserver: Any?

    // MARK: - Lifecycle

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
        rootView.autoresizingMask = [.width, .height]
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        createAllFields()
        setupUI()
        loadSettings()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let newSettings = notification.object as? Settings else { return }
            self.settings = newSettings
            self.reloadFromSettings()
        }
    }

    deinit {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Field Creation (all created eagerly)

    /// Creates every field once. They live for the lifetime of the view controller.
    /// Section builders reposition and reparent them into layout containers.
    private func createAllFields() {
        // Provider tiles
        geminiProviderButton = makeProviderTile("Gemini", tag: 0)
        openRouterProviderButton = makeProviderTile("OpenRouter", tag: 1)
        openAIProviderButton = makeProviderTile("OpenAI", tag: 2)
        anthropicProviderButton = makeProviderTile("Anthropic", tag: 3)

        fallbackCheckbox = NSButton(
            checkboxWithTitle: "Auto-fallback to alternative provider",
            target: self,
            action: #selector(fallbackChanged(_:))
        )

        // Shared provider detail
        providerApiKeyField = NSSecureTextField()
        providerApiKeyField.delegate = self

        providerModelField = NSTextField()
        providerModelField.delegate = self

        providerBaseURLField = NSTextField()
        providerBaseURLField.delegate = self

        detectModelButton = NSButton(title: "Detect", target: self, action: #selector(detectModelClicked(_:)))

        // Per-provider backing fields
        geminiApiKeyField = NSSecureTextField()
        geminiModelField = NSTextField()
        geminiBaseURLField = NSTextField()
        detectGeminiModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectGeminiModel(_:)))

        openRouterApiKeyField = NSSecureTextField()
        openRouterModelField = NSTextField()
        openRouterBaseURLField = NSTextField()
        detectOpenRouterModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectOpenRouterModel(_:)))

        openAIApiKeyField = NSSecureTextField()
        openAIModelField = NSTextField()
        openAIBaseURLField = NSTextField()
        openAIMaxAttemptsField = NSTextField()
        openAIMinSimilarityField = NSTextField()
        openAIExtraInstructionField = NSTextField()

        anthropicApiKeyField = NSSecureTextField()
        anthropicModelField = NSTextField()
        anthropicBaseURLField = NSTextField()
        anthropicMaxAttemptsField = NSTextField()
        anthropicMinSimilarityField = NSTextField()
        anthropicExtraInstructionField = NSTextField()

        // Hotkeys
        correctSelectionField = KeyComboField(frame: .zero)
        correctAllField = KeyComboField(frame: .zero)
        analyzeToneField = KeyComboField(frame: .zero)

        correctSelectionField.onChange = { [weak self] _ in self?.hotkeyDidChange() }
        correctAllField.onChange = { [weak self] _ in self?.hotkeyDidChange() }
        analyzeToneField.onChange = { [weak self] _ in self?.hotkeyDidChange() }

        // Advanced
        requestTimeoutField = NSTextField()
        requestTimeoutField.placeholderString = "20"
        requestTimeoutField.delegate = self

        languagePopup = NSPopUpButton()
        languagePopup.addItems(withTitles: ["Auto", "English (US)", "Indonesian"])
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        extraInstructionField = NSTextField()
        extraInstructionField.placeholderString = "Additional instructions for the AI..."
        extraInstructionField.cell = NSTextFieldCell()
        extraInstructionField.cell?.wraps = true
        extraInstructionField.isEditable = true
        extraInstructionField.isSelectable = true
        extraInstructionField.delegate = self

        geminiMinSimilarityField = NSTextField()
        openRouterMinSimilarityField = NSTextField()

        activeSimField = NSTextField()
        activeSimField.placeholderString = "0.65"
        activeSimField.delegate = self

        activeAttField = NSTextField()
        activeAttField.placeholderString = "2"
        activeAttField.delegate = self
    }

    private func makeProviderTile(_ title: String, tag: Int) -> NSButton {
        let button = NSButton()
        button.title = title
        button.bezelStyle = .rounded
        button.setButtonType(.onOff)
        button.tag = tag
        button.target = self
        button.action = #selector(providerTileClicked(_:))
        return button
    }

    // MARK: - UI Setup

    private func setupUI() {
        let padding: CGFloat = 20

        segmentedControl = NSSegmentedControl(
            labels: ["Provider", "Hotkeys", "Advanced", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(segmentChanged(_:))
        )
        segmentedControl.selectedSegment = 0
        segmentedControl.frame = NSRect(
            x: padding,
            y: view.frame.height - 44,
            width: view.frame.width - padding * 2,
            height: 28
        )
        segmentedControl.autoresizingMask = [.width, .minYMargin]
        view.addSubview(segmentedControl)

        let contentHeight = view.frame.height - 56
        contentContainer = NSView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: contentHeight))
        contentContainer.autoresizingMask = [.width, .height]
        view.addSubview(contentContainer)

        showSection(0)
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        showSection(sender.selectedSegment)
    }

    private func showSection(_ index: Int) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        switch index {
        case 0: contentContainer.addSubview(buildProviderSection())
        case 1: contentContainer.addSubview(buildHotkeysSection())
        case 2: contentContainer.addSubview(buildAdvancedSection())
        case 3: contentContainer.addSubview(buildAboutSection())
        default: break
        }
    }

    // MARK: - Provider Section Layout

    private func buildProviderSection() -> NSView {
        let container = NSView(frame: contentContainer.bounds)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - padding * 2
        let tileWidth = (contentWidth - 12) / 4
        let tileY = container.frame.height - 58

        // Provider tiles
        let tiles = [geminiProviderButton!, openRouterProviderButton!, openAIProviderButton!, anthropicProviderButton!]
        for (i, tile) in tiles.enumerated() {
            tile.frame = NSRect(x: padding + (tileWidth + 4) * CGFloat(i), y: tileY, width: tileWidth, height: 48)
            tile.autoresizingMask = [.width, .minYMargin]
            container.addSubview(tile)
        }

        // Detail box
        let detailBox = NSBox(frame: NSRect(x: padding, y: 20, width: contentWidth, height: tileY - 30))
        detailBox.boxType = .custom
        detailBox.cornerRadius = 8
        detailBox.borderColor = NSColor.separatorColor
        detailBox.borderWidth = 1
        detailBox.fillColor = NSColor.controlBackgroundColor
        detailBox.titlePosition = .noTitle
        detailBox.contentViewMargins = NSSize(width: 16, height: 12)
        detailBox.autoresizingMask = [.width, .height]
        container.addSubview(detailBox)

        let dc = detailBox.contentView!
        let dw = dc.frame.width
        let labelWidth: CGFloat = 80
        let fieldX = labelWidth + 8
        let fieldWidth = dw - fieldX - 8

        var y = dc.frame.height - 32

        // API Key
        let apiKeyLabel = createLabel("API Key", fontSize: 12, weight: .medium)
        apiKeyLabel.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 20)
        dc.addSubview(apiKeyLabel)

        providerApiKeyField.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 26)
        providerApiKeyField.autoresizingMask = [.width]
        dc.addSubview(providerApiKeyField)
        y -= 36

        // Model
        let modelLabel = createLabel("Model", fontSize: 12, weight: .medium)
        modelLabel.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 20)
        dc.addSubview(modelLabel)

        let detectWidth: CGFloat = 90
        providerModelField.frame = NSRect(x: fieldX, y: y, width: fieldWidth - detectWidth - 6, height: 26)
        providerModelField.autoresizingMask = [.width]
        dc.addSubview(providerModelField)

        detectModelButton.frame = NSRect(x: fieldX + fieldWidth - detectWidth, y: y, width: detectWidth, height: 26)
        detectModelButton.autoresizingMask = [.minXMargin]
        dc.addSubview(detectModelButton)
        y -= 36

        // Base URL
        let baseURLLabel = createLabel("Base URL", fontSize: 12, weight: .medium)
        baseURLLabel.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 20)
        dc.addSubview(baseURLLabel)

        providerBaseURLField.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 26)
        providerBaseURLField.autoresizingMask = [.width]
        dc.addSubview(providerBaseURLField)
        y -= 36

        // Fallback checkbox
        fallbackCheckbox.frame = NSRect(x: 0, y: y, width: dw, height: 20)
        fallbackCheckbox.autoresizingMask = [.width]
        dc.addSubview(fallbackCheckbox)

        updateProviderButtons()
        refreshProviderDetail()

        return container
    }

    private func refreshProviderDetail() {
        guard settings != nil else { return }
        let provider = settings.provider

        geminiProviderButton?.state = provider == .gemini ? .on : .off
        openRouterProviderButton?.state = provider == .openRouter ? .on : .off
        openAIProviderButton?.state = provider == .openAI ? .on : .off
        anthropicProviderButton?.state = provider == .anthropic ? .on : .off

        detectModelButton?.isHidden = !(provider == .gemini || provider == .openRouter)

        let account = apiKeyAccount(for: provider)
        providerApiKeyField?.stringValue = ""
        providerApiKeyField?.placeholderString = hasKeychainKey(account: account)
            ? "API key configured (leave blank to keep)"
            : "Enter API key"

        switch provider {
        case .gemini:
            providerModelField?.stringValue = settings.geminiModel
            providerModelField?.placeholderString = "gemini-2.5-flash"
            providerBaseURLField?.stringValue = settings.geminiBaseURL
            providerBaseURLField?.placeholderString = "https://generativelanguage.googleapis.com"
        case .openRouter:
            providerModelField?.stringValue = settings.openRouterModel
            providerModelField?.placeholderString = "google/gemma-3n-e4b-it:free"
            providerBaseURLField?.stringValue = settings.openRouterBaseURL
            providerBaseURLField?.placeholderString = "https://openrouter.ai/api/v1"
        case .openAI:
            providerModelField?.stringValue = settings.openAIModel
            providerModelField?.placeholderString = "gpt-5-nano"
            providerBaseURLField?.stringValue = settings.openAIBaseURL
            providerBaseURLField?.placeholderString = "https://api.openai.com/v1"
        case .anthropic:
            providerModelField?.stringValue = settings.anthropicModel
            providerModelField?.placeholderString = "claude-haiku-4-5"
            providerBaseURLField?.stringValue = settings.anthropicBaseURL
            providerBaseURLField?.placeholderString = "https://api.anthropic.com"
        }

        fallbackCheckbox?.state = settings.enableGeminiOpenRouterFallback ? .on : .off
        syncBackingFieldsFromSettings()
    }

    // MARK: - Hotkeys Section Layout

    private func buildHotkeysSection() -> NSView {
        let container = NSView(frame: contentContainer.bounds)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - padding * 2
        var y = container.frame.height - 32

        let titleLabel = createLabel("Hotkey Configuration", fontSize: 16, weight: .bold)
        titleLabel.frame = NSRect(x: padding, y: y, width: contentWidth, height: 24)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleLabel)
        y -= 22

        let instructionLabel = createLabel("Click a field and press desired key combination", fontSize: 11, weight: .regular)
        instructionLabel.frame = NSRect(x: padding, y: y, width: contentWidth, height: 17)
        instructionLabel.textColor = NSColor.secondaryLabelColor
        instructionLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(instructionLabel)
        y -= 40

        let labelWidth: CGFloat = 160
        let fieldX = padding + labelWidth + 8
        let fieldWidth = contentWidth - labelWidth - 8

        let rows: [(String, KeyComboField)] = [
            ("Correct Selection", correctSelectionField),
            ("Correct All", correctAllField),
            ("Analyze Tone", analyzeToneField),
        ]

        for (name, field) in rows {
            let label = createLabel(name, fontSize: 12, weight: .medium)
            label.frame = NSRect(x: padding, y: y + 5, width: labelWidth, height: 20)
            label.autoresizingMask = [.minYMargin]
            container.addSubview(label)

            field.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 30)
            field.autoresizingMask = [.width, .minYMargin]
            container.addSubview(field)
            y -= 44
        }

        if settings != nil {
            correctSelectionField.loadFromHotKey(settings.hotKeyCorrectSelection)
            correctAllField.loadFromHotKey(settings.hotKeyCorrectAll)
            analyzeToneField.loadFromHotKey(settings.hotKeyAnalyzeTone)
        }

        return container
    }

    // MARK: - Advanced Section Layout

    private func buildAdvancedSection() -> NSView {
        let container = NSView(frame: contentContainer.bounds)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - padding * 2
        let labelWidth: CGFloat = 140
        let fieldX = padding + labelWidth + 8

        var y = container.frame.height - 32

        // Request Timeout
        let timeoutLabel = createLabel("Request Timeout (s)", fontSize: 12, weight: .medium)
        timeoutLabel.frame = NSRect(x: padding, y: y + 3, width: labelWidth, height: 20)
        timeoutLabel.autoresizingMask = [.minYMargin]
        container.addSubview(timeoutLabel)

        requestTimeoutField.frame = NSRect(x: fieldX, y: y, width: 80, height: 26)
        requestTimeoutField.autoresizingMask = [.minYMargin]
        container.addSubview(requestTimeoutField)
        y -= 36

        // Correction Language
        let langLabel = createLabel("Correction Language", fontSize: 12, weight: .medium)
        langLabel.frame = NSRect(x: padding, y: y + 3, width: labelWidth, height: 20)
        langLabel.autoresizingMask = [.minYMargin]
        container.addSubview(langLabel)

        languagePopup.frame = NSRect(x: fieldX, y: y, width: 200, height: 26)
        languagePopup.autoresizingMask = [.minYMargin]
        container.addSubview(languagePopup)
        y -= 36

        // Extra Instruction
        let extraLabel = createLabel("Extra Instruction", fontSize: 12, weight: .medium)
        extraLabel.frame = NSRect(x: padding, y: y + 3, width: labelWidth, height: 20)
        extraLabel.autoresizingMask = [.minYMargin]
        container.addSubview(extraLabel)

        extraInstructionField.frame = NSRect(x: fieldX, y: y - 44, width: contentWidth - labelWidth - 8, height: 70)
        extraInstructionField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(extraInstructionField)
        y -= 86

        // Min Similarity
        let simLabel = createLabel("Min Similarity", fontSize: 12, weight: .medium)
        simLabel.frame = NSRect(x: padding, y: y + 3, width: labelWidth, height: 20)
        simLabel.autoresizingMask = [.minYMargin]
        container.addSubview(simLabel)

        activeSimField.frame = NSRect(x: fieldX, y: y, width: 80, height: 26)
        activeSimField.autoresizingMask = [.minYMargin]
        container.addSubview(activeSimField)
        y -= 36

        // Max Attempts
        let attLabel = createLabel("Max Attempts", fontSize: 12, weight: .medium)
        attLabel.frame = NSRect(x: padding, y: y + 3, width: labelWidth, height: 20)
        attLabel.autoresizingMask = [.minYMargin]
        container.addSubview(attLabel)

        activeAttField.frame = NSRect(x: fieldX, y: y, width: 80, height: 26)
        activeAttField.autoresizingMask = [.minYMargin]
        container.addSubview(activeAttField)

        if settings != nil {
            loadAdvancedFields()
        }

        return container
    }

    private func loadAdvancedFields() {
        requestTimeoutField.stringValue = String(format: "%.0f", settings.requestTimeoutSeconds)

        switch settings.correctionLanguage {
        case .auto: languagePopup.selectItem(at: 0)
        case .englishUS: languagePopup.selectItem(at: 1)
        case .indonesian: languagePopup.selectItem(at: 2)
        }

        switch settings.provider {
        case .gemini:
            extraInstructionField.stringValue = settings.geminiExtraInstruction ?? ""
            activeSimField.stringValue = String(format: "%.2f", settings.geminiMinSimilarity)
            activeAttField.stringValue = String(settings.geminiMaxAttempts)
        case .openRouter:
            extraInstructionField.stringValue = settings.openRouterExtraInstruction ?? ""
            activeSimField.stringValue = String(format: "%.2f", settings.openRouterMinSimilarity)
            activeAttField.stringValue = String(settings.openRouterMaxAttempts)
        case .openAI:
            extraInstructionField.stringValue = settings.openAIExtraInstruction ?? ""
            activeSimField.stringValue = String(format: "%.2f", settings.openAIMinSimilarity)
            activeAttField.stringValue = String(settings.openAIMaxAttempts)
        case .anthropic:
            extraInstructionField.stringValue = settings.anthropicExtraInstruction ?? ""
            activeSimField.stringValue = String(format: "%.2f", settings.anthropicMinSimilarity)
            activeAttField.stringValue = String(settings.anthropicMaxAttempts)
        }
    }

    private func buildAboutSection() -> NSView {
        let container = NSView(frame: contentContainer.bounds)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - padding * 2
        var y = container.frame.height - 32

        // App name + version
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
        let titleLabel = createLabel("TextPolish \(version)", fontSize: 18, weight: .bold)
        titleLabel.frame = NSRect(x: padding, y: y, width: contentWidth, height: 24)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(titleLabel)
        y -= 24

        let taglineLabel = createLabel(
            "Small, fast menu bar text polish for grammar and tone.",
            fontSize: 12, weight: .regular
        )
        taglineLabel.frame = NSRect(x: padding, y: y, width: contentWidth, height: 18)
        taglineLabel.textColor = .secondaryLabelColor
        taglineLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(taglineLabel)
        y -= 30

        // Privacy section
        let privacyTitle = createLabel("Privacy", fontSize: 14, weight: .semibold)
        privacyTitle.frame = NSRect(x: padding, y: y, width: contentWidth, height: 20)
        privacyTitle.autoresizingMask = [.width, .minYMargin]
        container.addSubview(privacyTitle)
        y -= 20

        let privacyItems = [
            "Text stays on-device until you trigger an action",
            "Sends only selected text to the provider over HTTPS",
            "API keys stored in macOS Keychain",
            "No analytics or telemetry",
            "TextPolish does not store your text",
        ]

        for item in privacyItems {
            let label = createLabel("\u{2022} \(item)", fontSize: 11, weight: .regular)
            label.frame = NSRect(x: padding + 8, y: y, width: contentWidth - 8, height: 15)
            label.textColor = .secondaryLabelColor
            label.autoresizingMask = [.width, .minYMargin]
            container.addSubview(label)
            y -= 16
        }
        y -= 10

        // Creator
        let creatorTitle = createLabel("Creator", fontSize: 14, weight: .semibold)
        creatorTitle.frame = NSRect(x: padding, y: y, width: contentWidth, height: 20)
        creatorTitle.autoresizingMask = [.width, .minYMargin]
        container.addSubview(creatorTitle)
        y -= 20

        let creatorLabel = createLabel("Kurniadi Ilham", fontSize: 12, weight: .regular)
        creatorLabel.frame = NSRect(x: padding, y: y, width: contentWidth, height: 18)
        creatorLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(creatorLabel)
        y -= 20

        let githubLabel = createLabel("github.com/kxxil01", fontSize: 11, weight: .regular)
        githubLabel.frame = NSRect(x: padding, y: y, width: contentWidth, height: 15)
        githubLabel.textColor = .linkColor
        githubLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(githubLabel)
        y -= 20

        // Info
        let settingsPath = Settings.settingsFileURL().path
        let infoLabel = createLabel("Settings: \(settingsPath)", fontSize: 10, weight: .regular)
        infoLabel.frame = NSRect(x: padding, y: y, width: contentWidth, height: 14)
        infoLabel.textColor = .tertiaryLabelColor
        infoLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(infoLabel)

        return container
    }

    // MARK: - Helpers

    private func createLabel(_ text: String, fontSize: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return label
    }

    private func apiKeyAccount(for provider: Settings.Provider) -> String {
        switch provider {
        case .gemini: return "geminiApiKey"
        case .openRouter: return "openRouterApiKey"
        case .openAI: return "openAIApiKey"
        case .anthropic: return "anthropicApiKey"
        }
    }

    private func apiKeyLabel(for provider: Settings.Provider) -> String {
        switch provider {
        case .gemini: return "TextPolish \u{2014} Gemini API Key"
        case .openRouter: return "TextPolish \u{2014} OpenRouter API Key"
        case .openAI: return "TextPolish \u{2014} OpenAI API Key"
        case .anthropic: return "TextPolish \u{2014} Anthropic API Key"
        }
    }

    // MARK: - Load / Reload Settings

    func loadSettings() {
        settings = Settings.loadOrCreateDefault()
        syncBackingFieldsFromSettings()
        reloadFromSettings()
    }

    private func reloadFromSettings() {
        refreshProviderDetail()
        correctSelectionField.loadFromHotKey(settings.hotKeyCorrectSelection)
        correctAllField.loadFromHotKey(settings.hotKeyCorrectAll)
        analyzeToneField.loadFromHotKey(settings.hotKeyAnalyzeTone)
        syncBackingFieldsFromSettings()
    }

    /// Keep backing fields in sync so tests can read them.
    private func syncBackingFieldsFromSettings() {
        guard settings != nil else { return }

        geminiModelField.stringValue = settings.geminiModel
        geminiBaseURLField.stringValue = settings.geminiBaseURL
        geminiApiKeyField.stringValue = ""
        geminiApiKeyField.placeholderString = hasKeychainKey(account: "geminiApiKey")
            ? "API key configured (leave blank to keep)"
            : "Enter your Gemini API key"

        openRouterModelField.stringValue = settings.openRouterModel
        openRouterBaseURLField.stringValue = settings.openRouterBaseURL
        openRouterApiKeyField.stringValue = ""
        openRouterApiKeyField.placeholderString = hasKeychainKey(account: "openRouterApiKey")
            ? "API key configured (leave blank to keep)"
            : "Enter your OpenRouter API key"

        openAIModelField.stringValue = settings.openAIModel
        openAIBaseURLField.stringValue = settings.openAIBaseURL
        openAIMaxAttemptsField.stringValue = String(settings.openAIMaxAttempts)
        openAIMinSimilarityField.stringValue = String(format: "%.2f", settings.openAIMinSimilarity)
        openAIExtraInstructionField.stringValue = settings.openAIExtraInstruction ?? ""
        openAIApiKeyField.stringValue = ""
        openAIApiKeyField.placeholderString = hasKeychainKey(account: "openAIApiKey")
            ? "API key configured (leave blank to keep)"
            : "Enter your OpenAI API key"

        anthropicModelField.stringValue = settings.anthropicModel
        anthropicBaseURLField.stringValue = settings.anthropicBaseURL
        anthropicMaxAttemptsField.stringValue = String(settings.anthropicMaxAttempts)
        anthropicMinSimilarityField.stringValue = String(format: "%.2f", settings.anthropicMinSimilarity)
        anthropicExtraInstructionField.stringValue = settings.anthropicExtraInstruction ?? ""
        anthropicApiKeyField.stringValue = ""
        anthropicApiKeyField.placeholderString = hasKeychainKey(account: "anthropicApiKey")
            ? "API key configured (leave blank to keep)"
            : "Enter your Anthropic API key"

        geminiMinSimilarityField.stringValue = String(format: "%.2f", settings.geminiMinSimilarity)
        openRouterMinSimilarityField.stringValue = String(format: "%.2f", settings.openRouterMinSimilarity)
    }

    // MARK: - Live Save

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, settings != nil else { return }

        if field === providerApiKeyField {
            saveCurrentProviderApiKey()
            return
        }
        if field === providerModelField {
            setCurrentProviderModel(providerModelField.stringValue)
            liveSave()
            return
        }
        if field === providerBaseURLField {
            setCurrentProviderBaseURL(providerBaseURLField.stringValue)
            liveSave()
            return
        }
        if field === requestTimeoutField {
            settings.requestTimeoutSeconds = Double(requestTimeoutField.stringValue) ?? 20
            liveSave()
            return
        }
        if field === extraInstructionField {
            setCurrentProviderExtraInstruction(extraInstructionField.stringValue)
            liveSave()
            return
        }
        if field === activeSimField {
            setCurrentProviderMinSimilarity(Double(field.stringValue) ?? 0.65)
            liveSave()
            return
        }
        if field === activeAttField {
            setCurrentProviderMaxAttempts(Int(field.stringValue) ?? 2)
            liveSave()
            return
        }
    }

    private func liveSave() {
        settings.normalizeRuntimeValues()
        do {
            try Settings.saveAndNotify(settings)
        } catch {
            TPLogger.log("Failed to live-save settings: \(error)")
            showErrorAlertIfNeeded(title: "Failed to save settings", message: error.localizedDescription)
        }
        syncBackingFieldsFromSettings()
        delegate?.settingsDidChange(settings)
    }

    private func hotkeyDidChange() {
        guard settings != nil else { return }
        let selection = correctSelectionField.hotKey ?? settings.hotKeyCorrectSelection
        let all = correctAllField.hotKey ?? settings.hotKeyCorrectAll
        let tone = analyzeToneField.hotKey ?? settings.hotKeyAnalyzeTone

        if let error = validateHotKeys(selection: selection, all: all, tone: tone, current: settings) {
            showErrorAlertIfNeeded(title: "Invalid hotkey", message: error)
            return
        }

        settings.hotKeyCorrectSelection = selection
        settings.hotKeyCorrectAll = all
        settings.hotKeyAnalyzeTone = tone
        liveSave()
    }

    private func saveCurrentProviderApiKey() {
        let value = providerApiKeyField.stringValue
        let provider = settings.provider
        do {
            try saveKeychainKeyIfNeeded(
                account: apiKeyAccount(for: provider),
                value: value,
                label: apiKeyLabel(for: provider)
            )
        } catch {
            showErrorAlertIfNeeded(title: "Failed to save API key", message: error.localizedDescription)
        }
        switch provider {
        case .gemini: settings.geminiApiKey = nil
        case .openRouter: settings.openRouterApiKey = nil
        case .openAI: settings.openAIApiKey = nil
        case .anthropic: settings.anthropicApiKey = nil
        }
        refreshProviderDetail()
    }

    private func setCurrentProviderModel(_ value: String) {
        switch settings.provider {
        case .gemini: settings.geminiModel = value
        case .openRouter: settings.openRouterModel = value
        case .openAI: settings.openAIModel = value
        case .anthropic: settings.anthropicModel = value
        }
    }

    private func setCurrentProviderBaseURL(_ value: String) {
        switch settings.provider {
        case .gemini: settings.geminiBaseURL = value
        case .openRouter: settings.openRouterBaseURL = value
        case .openAI: settings.openAIBaseURL = value
        case .anthropic: settings.anthropicBaseURL = value
        }
    }

    private func setCurrentProviderExtraInstruction(_ value: String) {
        let stored = value.isEmpty ? nil : value
        switch settings.provider {
        case .gemini: settings.geminiExtraInstruction = stored
        case .openRouter: settings.openRouterExtraInstruction = stored
        case .openAI: settings.openAIExtraInstruction = stored
        case .anthropic: settings.anthropicExtraInstruction = stored
        }
    }

    private func setCurrentProviderMinSimilarity(_ value: Double) {
        switch settings.provider {
        case .gemini: settings.geminiMinSimilarity = value
        case .openRouter: settings.openRouterMinSimilarity = value
        case .openAI: settings.openAIMinSimilarity = value
        case .anthropic: settings.anthropicMinSimilarity = value
        }
    }

    private func setCurrentProviderMaxAttempts(_ value: Int) {
        switch settings.provider {
        case .gemini: settings.geminiMaxAttempts = value
        case .openRouter: settings.openRouterMaxAttempts = value
        case .openAI: settings.openAIMaxAttempts = value
        case .anthropic: settings.anthropicMaxAttempts = value
        }
    }

    // MARK: - Actions

    @objc func providerTileClicked(_ sender: NSButton) {
        let providers: [Settings.Provider] = [.gemini, .openRouter, .openAI, .anthropic]
        guard sender.tag >= 0, sender.tag < providers.count else { return }
        settings.provider = providers[sender.tag]
        liveSave()
        refreshProviderDetail()
    }

    func updateProviderButtons() {
        guard settings != nil else { return }
        let provider = settings.provider
        geminiProviderButton.state = provider == .gemini ? .on : .off
        openRouterProviderButton.state = provider == .openRouter ? .on : .off
        openAIProviderButton.state = provider == .openAI ? .on : .off
        anthropicProviderButton.state = provider == .anthropic ? .on : .off
    }

    @objc func fallbackChanged(_ sender: NSButton) {
        guard settings != nil else { return }
        settings.enableGeminiOpenRouterFallback = sender.state == .on
        liveSave()
    }

    @objc func languageChanged(_ sender: NSPopUpButton) {
        guard settings != nil else { return }
        switch sender.indexOfSelectedItem {
        case 0: settings.correctionLanguage = .auto
        case 1: settings.correctionLanguage = .englishUS
        case 2: settings.correctionLanguage = .indonesian
        default: break
        }
        liveSave()
    }

    @objc private func detectModelClicked(_ sender: NSButton) {
        guard settings != nil else { return }
        switch settings.provider {
        case .gemini: detectGeminiModel(sender)
        case .openRouter: detectOpenRouterModel(sender)
        default: break
        }
    }

    // MARK: - Apply / Cancel (test compatibility)

    @objc func applyButtonClicked(_: NSButton) {
        if saveSettings() {
            settingsWindowController?.close()
        }
    }

    @objc func cancelButtonClicked(_: NSButton) {
        settingsWindowController?.close()
    }

    @discardableResult
    func saveSettings() -> Bool {
        guard var newSettings = settings else { return false }

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
        newSettings.enableGeminiOpenRouterFallback = fallbackCheckbox.state == .on

        // API keys
        do {
            try saveKeychainKeyIfNeeded(
                account: "geminiApiKey",
                value: geminiApiKeyField.stringValue,
                label: "TextPolish \u{2014} Gemini API Key"
            )
            newSettings.geminiApiKey = nil
            newSettings.geminiModel = geminiModelField.stringValue
            newSettings.geminiBaseURL = geminiBaseURLField.stringValue

            try saveKeychainKeyIfNeeded(
                account: "openRouterApiKey",
                value: openRouterApiKeyField.stringValue,
                label: "TextPolish \u{2014} OpenRouter API Key"
            )
            newSettings.openRouterApiKey = nil
            newSettings.openRouterModel = openRouterModelField.stringValue
            newSettings.openRouterBaseURL = openRouterBaseURLField.stringValue

            try saveKeychainKeyIfNeeded(
                account: "openAIApiKey",
                value: openAIApiKeyField.stringValue,
                label: "TextPolish \u{2014} OpenAI API Key"
            )
            newSettings.openAIApiKey = nil
            newSettings.openAIModel = openAIModelField.stringValue
            newSettings.openAIBaseURL = openAIBaseURLField.stringValue
            newSettings.openAIMaxAttempts = Int(openAIMaxAttemptsField.stringValue) ?? 2
            newSettings.openAIMinSimilarity = Double(openAIMinSimilarityField.stringValue) ?? 0.65
            newSettings.openAIExtraInstruction = openAIExtraInstructionField.stringValue.isEmpty
                ? nil : openAIExtraInstructionField.stringValue

            try saveKeychainKeyIfNeeded(
                account: "anthropicApiKey",
                value: anthropicApiKeyField.stringValue,
                label: "TextPolish \u{2014} Anthropic API Key"
            )
            newSettings.anthropicApiKey = nil
            newSettings.anthropicModel = anthropicModelField.stringValue
            newSettings.anthropicBaseURL = anthropicBaseURLField.stringValue
            newSettings.anthropicMaxAttempts = Int(anthropicMaxAttemptsField.stringValue) ?? 2
            newSettings.anthropicMinSimilarity = Double(anthropicMinSimilarityField.stringValue) ?? 0.65
            newSettings.anthropicExtraInstruction = anthropicExtraInstructionField.stringValue.isEmpty
                ? nil : anthropicExtraInstructionField.stringValue
        } catch {
            if NSClassFromString("XCTestCase") != nil {
                TPLogger.log("Keychain save error suppressed in test environment: \(error)")
            } else {
                showErrorAlertIfNeeded(
                    title: "Failed to save API key",
                    message: "Keychain rejected the API key update: \(error.localizedDescription)"
                )
                return false
            }
        }

        // Hotkeys
        let selectionHotKey = correctSelectionField.hotKey ?? newSettings.hotKeyCorrectSelection
        let allHotKey = correctAllField.hotKey ?? newSettings.hotKeyCorrectAll
        let toneHotKey = analyzeToneField.hotKey ?? newSettings.hotKeyAnalyzeTone
        if let hotKeyValidationError = validateHotKeys(
            selection: selectionHotKey,
            all: allHotKey,
            tone: toneHotKey,
            current: newSettings
        ) {
            showErrorAlertIfNeeded(title: "Invalid hotkeys", message: hotKeyValidationError)
            return false
        }
        newSettings.hotKeyCorrectSelection = selectionHotKey
        newSettings.hotKeyCorrectAll = allHotKey
        newSettings.hotKeyAnalyzeTone = toneHotKey

        // Advanced
        newSettings.requestTimeoutSeconds = Double(requestTimeoutField.stringValue) ?? 20
        newSettings.geminiMinSimilarity = Double(geminiMinSimilarityField.stringValue) ?? 0.65
        newSettings.openRouterMinSimilarity = Double(openRouterMinSimilarityField.stringValue) ?? 0.65

        switch languagePopup.indexOfSelectedItem {
        case 0: newSettings.correctionLanguage = .auto
        case 1: newSettings.correctionLanguage = .englishUS
        case 2: newSettings.correctionLanguage = .indonesian
        default: break
        }

        let extraValue = extraInstructionField.stringValue.isEmpty ? nil : extraInstructionField.stringValue
        switch newSettings.provider {
        case .gemini: newSettings.geminiExtraInstruction = extraValue
        case .openRouter: newSettings.openRouterExtraInstruction = extraValue
        case .openAI: newSettings.openAIExtraInstruction = extraValue
        case .anthropic: newSettings.anthropicExtraInstruction = extraValue
        }

        newSettings.normalizeRuntimeValues()
        do {
            try Settings.saveAndNotify(newSettings)
            settings = newSettings
        } catch {
            TPLogger.log("Failed to save settings from Settings window: \(error)")
            showErrorAlertIfNeeded(title: "Failed to save settings", message: error.localizedDescription)
            return false
        }
        delegate?.settingsDidChange(settings)
        return true
    }

    // MARK: - Hotkey Validation

    private func validateHotKeys(
        selection: Settings.HotKey,
        all: Settings.HotKey,
        tone: Settings.HotKey,
        current: Settings
    ) -> String? {
        let hotKeys: [(name: String, value: Settings.HotKey)] = [
            ("Correct Selection", selection),
            ("Correct All", all),
            ("Analyze Tone", tone),
        ]

        for hotKey in hotKeys {
            if hotKey.value.modifiers == 0 {
                return "\(hotKey.name) must include at least one modifier key (Control, Option, Command, or Shift)."
            }
        }

        if selection == all || selection == tone || all == tone {
            return "Hotkeys must be unique across Correct Selection, Correct All, and Analyze Tone."
        }

        let ignoredCurrent = [
            current.hotKeyCorrectSelection,
            current.hotKeyCorrectAll,
            current.hotKeyAnalyzeTone,
        ]

        for hotKey in hotKeys {
            let inUse = HotKeyManager.isHotKeyInUse(hotKey: hotKey.value, ignoring: ignoredCurrent)
            if inUse {
                return "\(hotKey.name) (\(hotKey.value.displayString)) is already used by another application."
            }
        }

        return nil
    }

    // MARK: - Keychain Helpers

    private var keychainService: String {
        Keychain.primaryService(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    private func hasKeychainKey(account: String) -> Bool {
        Keychain.hasConfiguredPassword(primaryService: keychainService, account: account)
    }

    private func keychainKey(account: String) -> String? {
        guard let key = try? Keychain.getConfiguredPassword(
            primaryService: keychainService,
            account: account
        ) else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func saveKeychainKeyIfNeeded(account: String, value: String, label: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try Keychain.setConfiguredPassword(
            trimmed,
            primaryService: keychainService,
            account: account,
            label: label
        )
    }

    private func showErrorAlertIfNeeded(title: String, message: String) {
        if NSClassFromString("XCTestCase") != nil {
            TPLogger.log("\(title): \(message)")
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Model Detection

    @objc func detectGeminiModel(_: NSButton) {
        detectModel(
            account: "geminiApiKey",
            backingKeyField: geminiApiKeyField,
            backingButton: detectGeminiModelButton,
            fallbackBaseURL: settings.geminiBaseURL,
            detect: ModelDetector.detectGeminiModel,
            applyModel: { [weak self] model in self?.settings?.geminiModel = model }
        )
    }

    @objc func detectOpenRouterModel(_: NSButton) {
        detectModel(
            account: "openRouterApiKey",
            backingKeyField: openRouterApiKeyField,
            backingButton: detectOpenRouterModelButton,
            fallbackBaseURL: settings.openRouterBaseURL,
            detect: ModelDetector.detectOpenRouterModel,
            applyModel: { [weak self] model in self?.settings?.openRouterModel = model }
        )
    }

    private func detectModel(
        account: String,
        backingKeyField: NSTextField,
        backingButton: NSButton,
        fallbackBaseURL: String,
        detect: @escaping (String, String) async throws -> String,
        applyModel: @escaping (String) -> Void
    ) {
        backingButton.isEnabled = false
        backingButton.title = "Detecting..."
        detectModelButton.isEnabled = false
        detectModelButton.title = "Detecting..."

        Task {
            do {
                var apiKey = providerApiKeyField.stringValue
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    apiKey = backingKeyField.stringValue
                }
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    apiKey = self.keychainKey(account: account) ?? ""
                }

                let baseURL = providerBaseURLField.stringValue.isEmpty
                    ? fallbackBaseURL : providerBaseURLField.stringValue
                let detectedModel = try await detect(apiKey, baseURL)

                await MainActor.run {
                    providerModelField.stringValue = detectedModel
                    applyModel(detectedModel)
                    backingButton.title = "Detect Model"
                    backingButton.isEnabled = true
                    detectModelButton.title = "Detect"
                    detectModelButton.isEnabled = true
                    syncBackingFieldsFromSettings()
                }
            } catch {
                await MainActor.run {
                    if NSClassFromString("XCTestCase") != nil {
                        TPLogger.log("Model detection error suppressed in test environment: \(error)")
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Failed to detect model"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                    backingButton.title = "Detect Model"
                    backingButton.isEnabled = true
                    detectModelButton.title = "Detect"
                    detectModelButton.isEnabled = true
                }
            }
        }
    }
}
