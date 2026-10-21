import AppKit

// Legacy hotspot: split this up before removing the suppression.
// swiftlint:disable file_length

protocol SettingsWindowViewControllerDelegate: AnyObject {
    func settingsDidChange(_ settings: Settings)
}

// swiftlint:disable:next type_body_length
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
    var geminiMaxAttemptsField: NSTextField!
    var geminiExtraInstructionField: NSTextField!
    var detectGeminiModelButton: NSButton!

    var openRouterApiKeyField: NSTextField!
    var openRouterModelField: NSTextField!
    var openRouterBaseURLField: NSTextField!
    var openRouterMaxAttemptsField: NSTextField!
    var openRouterExtraInstructionField: NSTextField!
    var detectOpenRouterModelButton: NSButton!

    var openAIApiKeyField: NSTextField!
    var openAIModelField: NSTextField!
    var openAIBaseURLField: NSTextField!
    var openAIMaxAttemptsField: NSTextField!
    var openAIMinSimilarityField: NSTextField!
    var openAIExtraInstructionField: NSTextField!
    var detectOpenAIModelButton: NSButton!

    var anthropicApiKeyField: NSTextField!
    var anthropicModelField: NSTextField!
    var anthropicBaseURLField: NSTextField!
    var anthropicMaxAttemptsField: NSTextField!
    var anthropicMinSimilarityField: NSTextField!
    var anthropicExtraInstructionField: NSTextField!
    var detectAnthropicModelButton: NSButton!

    // MARK: - Hotkey Fields

    var polishField: KeyComboField!
    var analyzeToneField: KeyComboField!

    // MARK: - Advanced Fields

    var requestTimeoutField: NSTextField!
    var languagePopup: NSPopUpButton!
    var polishStylePopup: NSPopUpButton!
    var protectedTermsField: NSTextField!
    var previewBeforePasteCheckbox: NSButton!
    var learnModeCheckbox: NSButton!
    var extraInstructionField: NSTextField!
    var geminiMinSimilarityField: NSTextField!
    var openRouterMinSimilarityField: NSTextField!

    // MARK: - Per-provider Advanced Fields (promoted from local vars — issue #5)

    var activeSimField: NSTextField!
    var activeAttField: NSTextField!

    // MARK: - State

    var settings: Settings!
    var keychainServiceOverride: String?
    weak var delegate: SettingsWindowViewControllerDelegate?
    weak var settingsWindowController: SettingsWindowController?
    private var settingsObserver: Any?
    private var currentSectionHeight: CGFloat = 0
    private let sectionBottomPadding: CGFloat = 20

    // MARK: - Lifecycle

    override func loadView() {
        let vibrancy = SettingsBackgroundView(frame: NSRect(x: 0, y: 0, width: 560, height: 480))
        vibrancy.material = .sidebar
        vibrancy.blendingMode = .behindWindow
        vibrancy.state = .active
        vibrancy.autoresizingMask = [.width, .height]
        // Tile layers hold fixed CGColors; restyle them when light/dark mode changes.
        vibrancy.onAppearanceChange = { [weak self] in self?.refreshProviderTiles() }
        view = vibrancy
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
            let providerChanged = self.settings?.provider != newSettings.provider
            self.settings = newSettings
            self.reloadFromSettings()
            // The Advanced tab's tuning card is titled for one provider; rebuild it when that changes.
            if providerChanged, self.segmentedControl.selectedSegment == 2 {
                self.showSection(2)
            }
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
        providerApiKeyField = PastableSecureTextField()
        providerApiKeyField.delegate = self

        providerModelField = NSTextField()
        providerModelField.delegate = self

        providerBaseURLField = NSTextField()
        providerBaseURLField.delegate = self

        detectModelButton = NSButton(title: "Detect", target: self, action: #selector(detectModelClicked(_:)))

        // Per-provider backing fields
        geminiApiKeyField = PastableSecureTextField()
        geminiModelField = NSTextField()
        geminiBaseURLField = NSTextField()
        geminiMaxAttemptsField = NSTextField()
        geminiExtraInstructionField = NSTextField()
        detectGeminiModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectGeminiModel(_:)))

        openRouterApiKeyField = PastableSecureTextField()
        openRouterModelField = NSTextField()
        openRouterBaseURLField = NSTextField()
        openRouterMaxAttemptsField = NSTextField()
        openRouterExtraInstructionField = NSTextField()
        detectOpenRouterModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectOpenRouterModel(_:)))

        openAIApiKeyField = PastableSecureTextField()
        openAIModelField = NSTextField()
        openAIBaseURLField = NSTextField()
        openAIMaxAttemptsField = NSTextField()
        openAIMinSimilarityField = NSTextField()
        openAIExtraInstructionField = NSTextField()
        detectOpenAIModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectOpenAIModel(_:)))

        anthropicApiKeyField = PastableSecureTextField()
        anthropicModelField = NSTextField()
        anthropicBaseURLField = NSTextField()
        anthropicMaxAttemptsField = NSTextField()
        anthropicMinSimilarityField = NSTextField()
        anthropicExtraInstructionField = NSTextField()
        detectAnthropicModelButton = NSButton(title: "Detect Model", target: self, action: #selector(detectAnthropicModel(_:)))

        // Hotkeys
        polishField = KeyComboField(frame: .zero)
        analyzeToneField = KeyComboField(frame: .zero)

        polishField.onChange = { [weak self] _ in self?.hotkeyDidChange() }
        analyzeToneField.onChange = { [weak self] _ in self?.hotkeyDidChange() }

        // Advanced
        requestTimeoutField = NSTextField()
        requestTimeoutField.placeholderString = "20"
        requestTimeoutField.delegate = self

        languagePopup = NSPopUpButton()
        languagePopup.addItems(withTitles: ["Auto", "English (US)", "Indonesian"])
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        polishStylePopup = NSPopUpButton()
        polishStylePopup.addItems(withTitles: Settings.PolishStyle.allCases.map(Self.polishStyleTitle))
        polishStylePopup.target = self
        polishStylePopup.action = #selector(polishStyleChanged(_:))

        protectedTermsField = NSTextField()
        protectedTermsField.placeholderString = "Names or terms to keep exactly, separated by commas"
        protectedTermsField.toolTip = "Polish never changes these words, for example names, product terms, or Indonesian words"
        protectedTermsField.delegate = self

        previewBeforePasteCheckbox = NSButton(
            checkboxWithTitle: "Show the changes and confirm before pasting",
            target: self,
            action: #selector(previewBeforePasteChanged(_:))
        )
        learnModeCheckbox = NSButton(
            checkboxWithTitle: "Explain the main changes after each Polish",
            target: self,
            action: #selector(learnModeChanged(_:))
        )

        // Keep the default bezeled cell so the field reads as editable; just let it wrap.
        extraInstructionField = NSTextField()
        extraInstructionField.placeholderString = "Optional, e.g. Keep British spelling"
        extraInstructionField.usesSingleLineMode = false
        extraInstructionField.cell?.wraps = true
        extraInstructionField.cell?.isScrollable = false
        extraInstructionField.lineBreakMode = .byWordWrapping
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
        button.title = ""
        button.bezelStyle = .smallSquare
        button.setButtonType(.onOff)
        button.isBordered = false
        button.tag = tag
        button.target = self
        button.action = #selector(providerTileClicked(_:))
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.setAccessibilityLabel(title)

        let sfNames = ["sparkle", "arrow.left.arrow.right", "circle.dotted", "diamond"]
        let sfName = sfNames[min(tag, sfNames.count - 1)]
        let symbolImage = NSImageView()
        if let img = NSImage(systemSymbolName: sfName, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            symbolImage.image = img.withSymbolConfiguration(config)
            symbolImage.contentTintColor = .secondaryLabelColor
        }
        symbolImage.imageAlignment = .alignCenter
        symbolImage.tag = 100
        button.addSubview(symbolImage)

        let nameLabel = NSTextField(labelWithString: title)
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.textColor = .labelColor
        nameLabel.tag = 101
        button.addSubview(nameLabel)

        let badge = NSTextField(labelWithString: "")
        badge.font = NSFont.systemFont(ofSize: 8, weight: .bold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.tag = 102
        button.addSubview(badge)

        return button
    }

    /// Icon above the name, key badge in the top-right corner. NSButton is flipped, so measure from the top.
    private func layoutTileSubviews(_ button: NSButton) {
        let width = button.bounds.width
        let height = button.bounds.height
        func originY(top: CGFloat, height itemHeight: CGFloat) -> CGFloat {
            button.isFlipped ? top : height - top - itemHeight
        }
        for sub in button.subviews {
            switch sub.tag {
            case 100: sub.frame = NSRect(x: (width - 24) / 2, y: originY(top: 10, height: 24), width: 24, height: 24)
            case 101: sub.frame = NSRect(x: 0, y: originY(top: 38, height: 16), width: width, height: 16)
            case 102:
                guard let badge = sub as? NSTextField else { break }
                let badgeWidth = max(badge.attributedStringValue.size().width + 10, 14)
                badge.frame = NSRect(x: width - badgeWidth - 6, y: originY(top: 6, height: 14), width: badgeWidth, height: 14)
            default: break
            }
        }
    }

    /// Selection shows as an accent border and tint; the green badge only means an API key is stored.
    private func styleProviderTile(_ button: NSButton, isActive: Bool, hasKey: Bool) {
        let providerName = button.accessibilityLabel() ?? ""
        let keyStatus = hasKey ? "API key stored" : "No API key"
        button.toolTip = "\(providerName): \(keyStatus)"
        button.setAccessibilityValue(isActive ? "Selected, \(keyStatus)" : keyStatus)

        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            button.layer?.borderWidth = isActive ? 2 : 1
            button.layer?.borderColor = isActive
                ? NSColor.controlAccentColor.cgColor
                : NSColor.separatorColor.cgColor
            button.layer?.backgroundColor = isActive
                ? NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
                : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        }

        if let symbolView = button.subviews.first(where: { $0.tag == 100 }) as? NSImageView {
            symbolView.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
        }
        if let nameLabel = button.subviews.first(where: { $0.tag == 101 }) as? NSTextField {
            nameLabel.textColor = isActive ? .controlAccentColor : .labelColor
        }

        guard let badge = button.subviews.first(where: { $0.tag == 102 }) as? NSTextField else { return }
        badge.stringValue = hasKey ? "\u{2713}" : ""
        badge.textColor = .white
        badge.effectiveAppearance.performAsCurrentDrawingAppearance {
            badge.layer?.backgroundColor = hasKey ? NSColor.systemGreen.cgColor : NSColor.clear.cgColor
        }
        layoutTileSubviews(button)
    }

    // MARK: - UI Setup

    private func setupUI() {
        let padding: CGFloat = 20
        let titleBarInset: CGFloat = 38

        segmentedControl = NSSegmentedControl(
            labels: ["Provider", "Hotkeys", "Advanced", "About"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(segmentChanged(_:))
        )
        segmentedControl.selectedSegment = 0
        segmentedControl.segmentStyle = .automatic
        segmentedControl.frame = NSRect(
            x: padding,
            y: view.frame.height - titleBarInset - 32,
            width: view.frame.width - padding * 2,
            height: 28
        )
        segmentedControl.autoresizingMask = [.width, .minYMargin]
        view.addSubview(segmentedControl)

        let contentTop = view.frame.height - titleBarInset - 44
        contentContainer = NSView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: contentTop))
        contentContainer.autoresizingMask = [.width, .height]
        view.addSubview(contentContainer)

        showSection(0)
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        commitPendingEdits()
        showSection(sender.selectedSegment)
    }

    /// Ends any in-progress text edit so its end-editing save runs before the UI changes underneath it.
    func commitPendingEdits() {
        view.window?.makeFirstResponder(nil)
    }

    private func showSection(_ index: Int) {
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let section: NSView
        switch index {
        case 0: section = buildProviderSection()
        case 1: section = buildHotkeysSection()
        case 2: section = buildAdvancedSection()
        case 3: section = buildAboutSection()
        default: return
        }
        contentContainer.addSubview(section)

        // Sections lay out from the top; measure down to the lowest subview plus a bottom margin.
        let lowestY = section.subviews.map(\.frame.minY).min() ?? 0
        currentSectionHeight = section.frame.height - lowestY + sectionBottomPadding
        fitWindowToSection(animated: view.window?.isVisible == true)
    }

    /// Resizes the window to the current section, keeping the top edge in place, so no tab leaves empty space.
    func fitWindowToSection(animated: Bool) {
        guard let window = view.window, currentSectionHeight > 0 else { return }
        let headerHeight = view.frame.height - contentContainer.frame.height
        let contentSize = NSSize(width: view.frame.width, height: headerHeight + currentSectionHeight)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.setFrame(frame, display: true, animate: animated)
    }

    // MARK: - Provider Section Layout

    private func buildProviderSection() -> NSView {
        let container = NSView(frame: contentContainer.bounds)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - padding * 2
        let tileGap: CGFloat = 8
        let tileWidth = (contentWidth - tileGap * 3) / 4
        let tileHeight: CGFloat = 64
        let tileY = container.frame.height - tileHeight - 4

        let tiles = [geminiProviderButton!, openRouterProviderButton!, openAIProviderButton!, anthropicProviderButton!]
        for (i, tile) in tiles.enumerated() {
            tile.frame = NSRect(x: padding + (tileWidth + tileGap) * CGFloat(i), y: tileY, width: tileWidth, height: tileHeight)
            tile.autoresizingMask = [.width, .minYMargin]
            container.addSubview(tile)
            layoutTileSubviews(tile)
        }

        let detailHeight: CGFloat = 164
        let detailY = tileY - detailHeight - 12
        let detailBox = SettingsUI.makeCard(frame: NSRect(x: padding, y: detailY, width: contentWidth, height: detailHeight))
        detailBox.contentViewMargins = NSSize(width: 16, height: 14)
        container.addSubview(detailBox)

        let detailContent = detailBox.contentView!
        let detailWidth = detailContent.frame.width
        let labelWidth: CGFloat = 80
        let fieldX = labelWidth + 8
        let fieldWidth = detailWidth - fieldX - 8

        var y = detailContent.frame.height - 32

        let apiKeyLabel = createLabel("API Key", fontSize: 12, weight: .medium)
        apiKeyLabel.textColor = .secondaryLabelColor
        apiKeyLabel.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 20)
        detailContent.addSubview(apiKeyLabel)

        providerApiKeyField.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 26)
        providerApiKeyField.autoresizingMask = [.width]
        detailContent.addSubview(providerApiKeyField)
        y -= 36

        let modelLabel = createLabel("Model", fontSize: 12, weight: .medium)
        modelLabel.textColor = .secondaryLabelColor
        modelLabel.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 20)
        detailContent.addSubview(modelLabel)

        let detectWidth: CGFloat = 100
        providerModelField.frame = NSRect(x: fieldX, y: y, width: fieldWidth - detectWidth - 8, height: 26)
        providerModelField.autoresizingMask = [.width]
        detailContent.addSubview(providerModelField)

        detectModelButton.bezelStyle = .rounded
        detectModelButton.frame = NSRect(x: fieldX + fieldWidth - detectWidth, y: y, width: detectWidth, height: 26)
        detectModelButton.autoresizingMask = [.minXMargin]
        detailContent.addSubview(detectModelButton)
        y -= 36

        let baseURLLabel = createLabel("Base URL", fontSize: 12, weight: .medium)
        baseURLLabel.textColor = .secondaryLabelColor
        baseURLLabel.frame = NSRect(x: 0, y: y + 3, width: labelWidth, height: 20)
        detailContent.addSubview(baseURLLabel)

        providerBaseURLField.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 26)
        providerBaseURLField.autoresizingMask = [.width]
        detailContent.addSubview(providerBaseURLField)
        y -= 36

        fallbackCheckbox.frame = NSRect(x: 0, y: y + 4, width: detailWidth, height: 20)
        fallbackCheckbox.autoresizingMask = [.width]
        detailContent.addSubview(fallbackCheckbox)

        updateProviderButtons()
        refreshProviderDetail()

        return container
    }

    private func refreshProviderDetail() {
        guard settings != nil else { return }
        let provider = settings.provider

        refreshProviderTiles()

        detectModelButton?.isHidden = false

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
            providerModelField?.placeholderString = "gpt-4.1-mini"
            providerBaseURLField?.stringValue = settings.openAIBaseURL
            providerBaseURLField?.placeholderString = "https://api.openai.com/v1"
        case .anthropic:
            providerModelField?.stringValue = settings.anthropicModel
            providerModelField?.placeholderString = "claude-haiku-4-5"
            providerBaseURLField?.stringValue = settings.anthropicBaseURL
            providerBaseURLField?.placeholderString = "https://api.anthropic.com"
        }

        fallbackCheckbox?.state = settings.enableGeminiOpenRouterFallback ? .on : .off
        fallbackCheckbox?.title = fallbackTitle(for: provider)
        syncBackingFieldsFromSettings()
        loadAdvancedFields()
    }

    /// Fallback pairs Gemini with OpenRouter and OpenAI with Anthropic, and needs the partner's API key.
    private func fallbackTitle(for provider: Settings.Provider) -> String {
        let partner: Settings.Provider
        switch provider {
        case .gemini: partner = .openRouter
        case .openRouter: partner = .gemini
        case .openAI: partner = .anthropic
        case .anthropic: partner = .openAI
        }
        let title = "If \(provider.displayName) fails, retry with \(partner.displayName)"
        if hasKeychainKey(account: apiKeyAccount(for: partner)) {
            return title
        }
        return title + " (needs an API key for \(partner.displayName))"
    }

    private func refreshProviderTiles() {
        guard settings != nil else { return }
        let provider = settings.provider
        let providerButtons: [(NSButton?, Settings.Provider)] = [
            (geminiProviderButton, .gemini),
            (openRouterProviderButton, .openRouter),
            (openAIProviderButton, .openAI),
            (anthropicProviderButton, .anthropic),
        ]
        for (button, buttonProvider) in providerButtons {
            guard let button else { continue }
            button.state = provider == buttonProvider ? .on : .off
            let hasKey = hasKeychainKey(account: apiKeyAccount(for: buttonProvider))
            styleProviderTile(button, isActive: provider == buttonProvider, hasKey: hasKey)
        }
    }

    // MARK: - Hotkeys Section Layout

    private func buildHotkeysSection() -> NSView {
        let container = NSView(frame: contentContainer.bounds)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - padding * 2
        var y = container.frame.height - 4

        let instructionLabel = SettingsUI.makeHint("Click a shortcut, then press the new key combination. Esc cancels.")
        instructionLabel.frame = NSRect(x: padding + 4, y: y - 16, width: contentWidth - 4, height: 16)
        instructionLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(instructionLabel)
        y -= 24

        let rows: [(String, KeyComboField)] = [
            ("Polish", polishField),
            ("Analyze Tone", analyzeToneField),
        ]
        let rowPitch: CGFloat = 44
        let contentHeight = CGFloat(rows.count - 1) * rowPitch + 26
        let cardHeight = contentHeight + 24
        let card = SettingsUI.makeCard(frame: NSRect(x: padding, y: y - cardHeight, width: contentWidth, height: cardHeight))
        container.addSubview(card)

        let cardContent = card.contentView!
        var rowY = cardContent.frame.height - 26
        for (index, (name, field)) in rows.enumerated() {
            addRow(to: cardContent, label: name, y: rowY, control: field, controlWidth: nil)
            field.setAccessibilityLabel(name)
            if index < rows.count - 1 {
                addSeparator(to: cardContent, y: rowY - (rowPitch - 26) / 2)
            }
            rowY -= rowPitch
        }

        if settings != nil {
            loadHotKeyFields(from: settings)
        }

        return container
    }

    // MARK: - Advanced Section Layout

    private func buildAdvancedSection() -> NSView {
        let container = NSView(frame: contentContainer.bounds)
        container.autoresizingMask = [.width, .height]

        let padding: CGFloat = 20
        let contentWidth = container.frame.width - padding * 2
        var y = container.frame.height - 4

        // General: applies to every provider.
        let generalHeader = SettingsUI.makeSectionHeader("General")
        generalHeader.frame = NSRect(x: padding + 4, y: y - 16, width: contentWidth - 4, height: 16)
        container.addSubview(generalHeader)
        y -= 22

        let generalHeight: CGFloat = 206 + 24
        let generalCard = SettingsUI.makeCard(frame: NSRect(x: padding, y: y - generalHeight, width: contentWidth, height: generalHeight))
        container.addSubview(generalCard)
        let general = generalCard.contentView!
        addRow(to: general, label: "Polish Style", y: 180, control: polishStylePopup, controlWidth: nil)
        addSeparator(to: general, y: 175)
        addRow(to: general, label: "Learn", y: 144, control: learnModeCheckbox, controlWidth: nil)
        addSeparator(to: general, y: 139)
        addRow(to: general, label: "Preview", y: 108, control: previewBeforePasteCheckbox, controlWidth: nil)
        addSeparator(to: general, y: 103)
        addRow(to: general, label: "Never Change", y: 72, control: protectedTermsField, controlWidth: nil)
        addSeparator(to: general, y: 67)
        addRow(to: general, label: "Request Timeout", y: 36, control: requestTimeoutField, controlWidth: 80, hint: "seconds, 1 to 120")
        addSeparator(to: general, y: 31)
        addRow(to: general, label: "Correction Language", y: 0, control: languagePopup, controlWidth: nil)
        y -= generalHeight + 16

        // Tuning: stored separately for each provider.
        let providerName = settings?.provider.displayName ?? "Provider"
        let tuningHeader = SettingsUI.makeSectionHeader("\(providerName) tuning")
        tuningHeader.frame = NSRect(x: padding + 4, y: y - 16, width: contentWidth - 4, height: 16)
        container.addSubview(tuningHeader)
        y -= 22

        let tuningHeight: CGFloat = 126 + 24
        let tuningCard = SettingsUI.makeCard(frame: NSRect(x: padding, y: y - tuningHeight, width: contentWidth, height: tuningHeight))
        container.addSubview(tuningCard)
        let tuning = tuningCard.contentView!
        addRow(to: tuning, label: "Extra Instruction", y: 72, control: extraInstructionField, controlWidth: nil, controlHeight: 54)
        let extraHint = SettingsUI.makeHint("Up to 500 characters")
        extraHint.frame = NSRect(x: 0, y: 84, width: settingsLabelWidth, height: 15)
        tuning.addSubview(extraHint)
        addSeparator(to: tuning, y: 67)
        addRow(
            to: tuning, label: "Min Similarity", y: 36, control: activeSimField, controlWidth: 80,
            hint: "0 to 1, higher allows fewer changes"
        )
        addSeparator(to: tuning, y: 31)
        addRow(to: tuning, label: "Max Attempts", y: 0, control: activeAttField, controlWidth: 80, hint: "1 to 8 tries per correction")

        if settings != nil {
            loadAdvancedFields()
        }

        return container
    }

    // MARK: - Row Helpers

    private let settingsLabelWidth: CGFloat = 140

    /// Adds a label and control on one row. Multi-line controls align their label with the top line.
    private func addRow(
        to parent: NSView,
        label text: String,
        y: CGFloat,
        control: NSView,
        controlWidth: CGFloat?,
        controlHeight: CGFloat = 26,
        hint: String? = nil
    ) {
        let label = createLabel(text, fontSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 0, y: y + controlHeight - 23, width: settingsLabelWidth, height: 20)
        parent.addSubview(label)

        let controlX = settingsLabelWidth + 8
        let width = controlWidth ?? (parent.frame.width - controlX)
        control.frame = NSRect(x: controlX, y: y, width: width, height: controlHeight)
        control.autoresizingMask = controlWidth == nil ? [.width] : []
        parent.addSubview(control)

        guard let hint else { return }
        let hintLabel = SettingsUI.makeHint(hint)
        let hintX = controlX + width + 8
        hintLabel.frame = NSRect(x: hintX, y: y + 5, width: max(0, parent.frame.width - hintX), height: 15)
        hintLabel.autoresizingMask = [.width]
        parent.addSubview(hintLabel)
    }

    private func addSeparator(to parent: NSView, y: CGFloat) {
        let separator = NSBox(frame: NSRect(x: 0, y: y, width: parent.frame.width, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width]
        parent.addSubview(separator)
    }

    private static func polishStyleTitle(_ style: Settings.PolishStyle) -> String {
        switch style {
        case .natural: return "Natural: improve wording and flow"
        case .minimal: return "Minimal: fix errors only"
        case .shorter: return "Shorter: cut filler, keep every point"
        case .formal: return "Formal: polite and professional"
        case .friendly: return "Friendly: warm and casual"
        }
    }

    private func loadAdvancedFields() {
        requestTimeoutField.stringValue = String(format: "%.0f", settings.requestTimeoutSeconds)
        polishStylePopup.selectItem(at: Settings.PolishStyle.allCases.firstIndex(of: settings.polishStyle) ?? 0)
        protectedTermsField.stringValue = settings.protectedTerms.joined(separator: ", ")
        previewBeforePasteCheckbox.state = settings.previewBeforePaste ? .on : .off
        learnModeCheckbox.state = settings.learnMode ? .on : .off

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
        var y = container.frame.height - 28

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
        y -= 22

        let githubLink = SettingsLinkButton(
            title: "github.com/kxxil01",
            fontSize: 12,
            target: self,
            action: #selector(openGitHubProfile(_:))
        )
        githubLink.sizeToFit()
        githubLink.frame.origin = NSPoint(x: padding, y: y)
        githubLink.autoresizingMask = [.minYMargin]
        container.addSubview(githubLink)
        y -= 28

        // Settings file location, revealed in Finder instead of printing a long path.
        let settingsLink = SettingsLinkButton(
            title: "Show settings file in Finder",
            fontSize: 11,
            target: self,
            action: #selector(revealSettingsFile(_:))
        )
        settingsLink.toolTip = Settings.settingsFileURL().path
        settingsLink.sizeToFit()
        settingsLink.frame.origin = NSPoint(x: padding, y: y)
        settingsLink.autoresizingMask = [.minYMargin]
        container.addSubview(settingsLink)

        return container
    }

    @objc private func openGitHubProfile(_: Any?) {
        guard let url = URL(string: "https://github.com/kxxil01") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealSettingsFile(_: Any?) {
        let url = Settings.settingsFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
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
        loadHotKeyFields(from: settings)
        loadAdvancedFields()
        syncBackingFieldsFromSettings()
    }

    /// Keep backing fields in sync so tests can read them.
    private func syncBackingFieldsFromSettings() {
        guard settings != nil else { return }

        geminiModelField.stringValue = settings.geminiModel
        geminiBaseURLField.stringValue = settings.geminiBaseURL
        geminiMaxAttemptsField.stringValue = String(settings.geminiMaxAttempts)
        geminiMinSimilarityField.stringValue = String(format: "%.2f", settings.geminiMinSimilarity)
        geminiExtraInstructionField.stringValue = settings.geminiExtraInstruction ?? ""
        geminiApiKeyField.stringValue = ""
        geminiApiKeyField.placeholderString = hasKeychainKey(account: "geminiApiKey")
            ? "API key configured (leave blank to keep)"
            : "Enter your Gemini API key"

        openRouterModelField.stringValue = settings.openRouterModel
        openRouterBaseURLField.stringValue = settings.openRouterBaseURL
        openRouterMaxAttemptsField.stringValue = String(settings.openRouterMaxAttempts)
        openRouterMinSimilarityField.stringValue = String(format: "%.2f", settings.openRouterMinSimilarity)
        openRouterExtraInstructionField.stringValue = settings.openRouterExtraInstruction ?? ""
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
        if field === protectedTermsField {
            settings.protectedTerms = Settings.parseProtectedTerms(protectedTermsField.stringValue)
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
        guard var updated = settings else { return }
        applyHotKeyFields(to: &updated)

        if let error = validateHotKeys(in: updated, current: settings) {
            loadHotKeyFields(from: settings)
            showErrorAlertIfNeeded(title: "Invalid hotkey", message: error)
            return
        }

        settings = updated
        liveSave()
    }

    private func loadHotKeyFields(from settings: Settings) {
        polishField.loadFromHotKey(settings.hotKeyPolish)
        analyzeToneField.loadFromHotKey(settings.hotKeyAnalyzeTone)
    }

    /// Copies the hotkey fields into `settings`; an empty field keeps the existing value.
    private func applyHotKeyFields(to settings: inout Settings) {
        settings.hotKeyPolish = polishField.hotKey ?? settings.hotKeyPolish
        settings.hotKeyAnalyzeTone = analyzeToneField.hotKey ?? settings.hotKeyAnalyzeTone
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

    private func minSimilarity(in settings: Settings, provider: Settings.Provider) -> Double {
        switch provider {
        case .gemini: return settings.geminiMinSimilarity
        case .openRouter: return settings.openRouterMinSimilarity
        case .openAI: return settings.openAIMinSimilarity
        case .anthropic: return settings.anthropicMinSimilarity
        }
    }

    private func maxAttempts(in settings: Settings, provider: Settings.Provider) -> Int {
        switch provider {
        case .gemini: return settings.geminiMaxAttempts
        case .openRouter: return settings.openRouterMaxAttempts
        case .openAI: return settings.openAIMaxAttempts
        case .anthropic: return settings.anthropicMaxAttempts
        }
    }

    // MARK: - Actions

    @objc func providerTileClicked(_ sender: NSButton) {
        let providers: [Settings.Provider] = [.gemini, .openRouter, .openAI, .anthropic]
        guard sender.tag >= 0, sender.tag < providers.count else { return }
        commitPendingEdits()
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

    @objc func polishStyleChanged(_ sender: NSPopUpButton) {
        guard settings != nil, Settings.PolishStyle.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.polishStyle = Settings.PolishStyle.allCases[sender.indexOfSelectedItem]
        liveSave()
    }

    @objc func previewBeforePasteChanged(_ sender: NSButton) {
        guard settings != nil else { return }
        settings.previewBeforePaste = sender.state == .on
        liveSave()
    }

    @objc func learnModeChanged(_ sender: NSButton) {
        guard settings != nil else { return }
        settings.learnMode = sender.state == .on
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
        case .openAI: detectOpenAIModel(sender)
        case .anthropic: detectAnthropicModel(sender)
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
    // Legacy hotspot: split this up before removing the suppression.
    // swiftlint:disable:next function_body_length
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
        let previousActiveMinSimilarity = minSimilarity(in: settings, provider: newSettings.provider)
        let previousActiveMaxAttempts = maxAttempts(in: settings, provider: newSettings.provider)

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
            newSettings.geminiMaxAttempts = Int(geminiMaxAttemptsField.stringValue) ?? newSettings.geminiMaxAttempts
            newSettings.geminiMinSimilarity = Double(geminiMinSimilarityField.stringValue) ?? newSettings.geminiMinSimilarity
            newSettings.geminiExtraInstruction = geminiExtraInstructionField.stringValue.isEmpty
                ? nil : geminiExtraInstructionField.stringValue

            try saveKeychainKeyIfNeeded(
                account: "openRouterApiKey",
                value: openRouterApiKeyField.stringValue,
                label: "TextPolish \u{2014} OpenRouter API Key"
            )
            newSettings.openRouterApiKey = nil
            newSettings.openRouterModel = openRouterModelField.stringValue
            newSettings.openRouterBaseURL = openRouterBaseURLField.stringValue
            newSettings.openRouterMaxAttempts = Int(openRouterMaxAttemptsField.stringValue) ?? newSettings.openRouterMaxAttempts
            newSettings.openRouterMinSimilarity = Double(openRouterMinSimilarityField.stringValue) ?? newSettings.openRouterMinSimilarity
            newSettings.openRouterExtraInstruction = openRouterExtraInstructionField.stringValue.isEmpty
                ? nil : openRouterExtraInstructionField.stringValue

            try saveKeychainKeyIfNeeded(
                account: "openAIApiKey",
                value: openAIApiKeyField.stringValue,
                label: "TextPolish \u{2014} OpenAI API Key"
            )
            newSettings.openAIApiKey = nil
            newSettings.openAIModel = openAIModelField.stringValue
            newSettings.openAIBaseURL = openAIBaseURLField.stringValue
            newSettings.openAIMaxAttempts = Int(openAIMaxAttemptsField.stringValue) ?? newSettings.openAIMaxAttempts
            newSettings.openAIMinSimilarity = Double(openAIMinSimilarityField.stringValue) ?? newSettings.openAIMinSimilarity
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
            newSettings.anthropicMaxAttempts = Int(anthropicMaxAttemptsField.stringValue) ?? newSettings.anthropicMaxAttempts
            newSettings.anthropicMinSimilarity = Double(anthropicMinSimilarityField.stringValue) ?? newSettings.anthropicMinSimilarity
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
        let currentHotKeys = newSettings
        applyHotKeyFields(to: &newSettings)
        if let hotKeyValidationError = validateHotKeys(in: newSettings, current: currentHotKeys) {
            showErrorAlertIfNeeded(title: "Invalid hotkeys", message: hotKeyValidationError)
            return false
        }

        // Advanced
        newSettings.requestTimeoutSeconds = Double(requestTimeoutField.stringValue) ?? 20
        newSettings.protectedTerms = Settings.parseProtectedTerms(protectedTermsField.stringValue)
        newSettings.previewBeforePaste = previewBeforePasteCheckbox.state == .on
        newSettings.learnMode = learnModeCheckbox.state == .on
        if Settings.PolishStyle.allCases.indices.contains(polishStylePopup.indexOfSelectedItem) {
            newSettings.polishStyle = Settings.PolishStyle.allCases[polishStylePopup.indexOfSelectedItem]
        }

        switch languagePopup.indexOfSelectedItem {
        case 0: newSettings.correctionLanguage = .auto
        case 1: newSettings.correctionLanguage = .englishUS
        case 2: newSettings.correctionLanguage = .indonesian
        default: break
        }

        let extraValue = extraInstructionField.stringValue.isEmpty ? nil : extraInstructionField.stringValue
        let parsedActiveMinSimilarity = Double(activeSimField.stringValue)
        let parsedActiveMaxAttempts = Int(activeAttField.stringValue)
        let activeMinSimilarity = parsedActiveMinSimilarity.flatMap { abs($0 - previousActiveMinSimilarity) > 0.000_001 ? $0 : nil }
        let activeMaxAttempts = parsedActiveMaxAttempts.flatMap { $0 != previousActiveMaxAttempts ? $0 : nil }
        switch newSettings.provider {
        case .gemini:
            newSettings.geminiExtraInstruction = extraValue
            if let activeMinSimilarity { newSettings.geminiMinSimilarity = activeMinSimilarity }
            if let activeMaxAttempts { newSettings.geminiMaxAttempts = activeMaxAttempts }
        case .openRouter:
            newSettings.openRouterExtraInstruction = extraValue
            if let activeMinSimilarity { newSettings.openRouterMinSimilarity = activeMinSimilarity }
            if let activeMaxAttempts { newSettings.openRouterMaxAttempts = activeMaxAttempts }
        case .openAI:
            newSettings.openAIExtraInstruction = extraValue
            if let activeMinSimilarity { newSettings.openAIMinSimilarity = activeMinSimilarity }
            if let activeMaxAttempts { newSettings.openAIMaxAttempts = activeMaxAttempts }
        case .anthropic:
            newSettings.anthropicExtraInstruction = extraValue
            if let activeMinSimilarity { newSettings.anthropicMinSimilarity = activeMinSimilarity }
            if let activeMaxAttempts { newSettings.anthropicMaxAttempts = activeMaxAttempts }
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

    private static func namedHotKeys(in settings: Settings) -> [(name: String, value: Settings.HotKey)] {
        [
            ("Polish", settings.hotKeyPolish),
            ("Analyze Tone", settings.hotKeyAnalyzeTone),
        ]
    }

    private func validateHotKeys(in candidate: Settings, current: Settings) -> String? {
        let hotKeys = Self.namedHotKeys(in: candidate)

        for hotKey in hotKeys where hotKey.value.modifiers == 0 {
            return "\(hotKey.name) must include at least one modifier key (Control, Option, Command, or Shift)."
        }

        for (index, hotKey) in hotKeys.enumerated() {
            if let other = hotKeys[(index + 1)...].first(where: { $0.value == hotKey.value }) {
                return "\(hotKey.name) and \(other.name) both use \(hotKey.value.displayString). Hotkeys must be unique."
            }
        }

        let ignoredCurrent = Self.namedHotKeys(in: current).map(\.value)

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
        keychainServiceOverride ?? Keychain.primaryService(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    private func hasKeychainKey(account: String) -> Bool {
        Keychain.hasConfiguredPassword(primaryService: keychainService, account: account)
    }

    private func keychainKey(account: String) async -> String? {
        guard let key = await Keychain.loadConfiguredPassword(
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
            provider: .gemini,
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
            provider: .openRouter,
            account: "openRouterApiKey",
            backingKeyField: openRouterApiKeyField,
            backingButton: detectOpenRouterModelButton,
            fallbackBaseURL: settings.openRouterBaseURL,
            detect: ModelDetector.detectOpenRouterModel,
            applyModel: { [weak self] model in self?.settings?.openRouterModel = model }
        )
    }

    @objc func detectOpenAIModel(_: NSButton) {
        detectModel(
            provider: .openAI,
            account: "openAIApiKey",
            backingKeyField: openAIApiKeyField,
            backingButton: detectOpenAIModelButton,
            fallbackBaseURL: settings.openAIBaseURL,
            detect: ModelDetector.detectOpenAIModel,
            applyModel: { [weak self] model in self?.settings?.openAIModel = model }
        )
    }

    @objc func detectAnthropicModel(_: NSButton) {
        detectModel(
            provider: .anthropic,
            account: "anthropicApiKey",
            backingKeyField: anthropicApiKeyField,
            backingButton: detectAnthropicModelButton,
            fallbackBaseURL: settings.anthropicBaseURL,
            detect: ModelDetector.detectAnthropicModel,
            applyModel: { [weak self] model in self?.settings?.anthropicModel = model }
        )
    }

    private func detectModel(
        provider: Settings.Provider,
        account: String,
        backingKeyField: NSTextField,
        backingButton: NSButton,
        fallbackBaseURL: String,
        detect: @escaping (String, String) async throws -> String,
        applyModel: @escaping (String) -> Void
    ) {
        var typedKey = providerApiKeyField.stringValue
        if typedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            typedKey = backingKeyField.stringValue
        }
        guard !typedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasKeychainKey(account: account) else {
            showErrorAlertIfNeeded(
                title: "API key needed",
                message: "Enter an API key for \(provider.displayName) before detecting a model."
            )
            return
        }

        backingButton.isEnabled = false
        backingButton.title = "Detecting..."
        detectModelButton.isEnabled = false
        detectModelButton.title = "Detecting..."

        let baseURL = providerBaseURLField.stringValue.isEmpty
            ? fallbackBaseURL : providerBaseURLField.stringValue

        Task {
            var apiKey = typedKey
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                apiKey = await self.keychainKey(account: account) ?? ""
            }
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                backingButton.title = "Detect Model"
                backingButton.isEnabled = true
                self.detectModelButton.title = "Detect"
                self.detectModelButton.isEnabled = true
                self.showErrorAlertIfNeeded(
                    title: "API key needed",
                    message: "Enter an API key for \(provider.displayName) before detecting a model."
                )
                return
            }
            do {
                let detectedModel = try await detect(apiKey, baseURL)

                await MainActor.run {
                    applyModel(detectedModel)
                    if self.settings.provider == provider {
                        self.providerModelField.stringValue = detectedModel
                    }
                    self.liveSave()
                    backingButton.title = "Detect Model"
                    backingButton.isEnabled = true
                    self.detectModelButton.title = "Detect"
                    self.detectModelButton.isEnabled = true
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
                    self.detectModelButton.title = "Detect"
                    self.detectModelButton.isEnabled = true
                }
            }
        }
    }
}
