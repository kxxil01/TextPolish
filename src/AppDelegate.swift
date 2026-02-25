import AppKit
import ServiceManagement
import Carbon
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let hotKeyManager = HotKeyManager()

  private var baseImage: NSImage?
  private var settings = Settings.loadOrCreateDefault()
  private var correctionController: CorrectionController?
  private var toneAnalysisController: ToneAnalysisController?
  private var toneResultWindow: ToneAnalysisResultWindow?
  private var diagnosticsWindow: DiagnosticsWindow?
  private var feedback: StatusItemFeedback?
  private var statusMenu: NSMenu?
  private var lastTargetApplication: NSRunningApplication?
  private var workspaceActivationObserver: Any?
  private var isMenuOpen = false
  private var pendingAfterMenuAction: (@MainActor () async -> Void)?
  private var settingsWindowController: SettingsWindowController?
  private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: self,
    userDriverDelegate: nil
  )

  private var providerGeminiItem: NSMenuItem?
  private var providerOpenRouterItem: NSMenuItem?
  private var providerOpenAIItem: NSMenuItem?
  private var providerAnthropicItem: NSMenuItem?
  private var setGeminiKeyItem: NSMenuItem?
  private var setGeminiModelItem: NSMenuItem?
  private var detectGeminiModelItem: NSMenuItem?
  private var setOpenRouterKeyItem: NSMenuItem?
  private var setOpenRouterModelItem: NSMenuItem?
  private var detectOpenRouterModelItem: NSMenuItem?
  private var setOpenAIKeyItem: NSMenuItem?
  private var setOpenAIModelItem: NSMenuItem?
  private var setAnthropicKeyItem: NSMenuItem?
  private var setAnthropicModelItem: NSMenuItem?
  private var providerHealthItem: NSMenuItem?
  private var launchAtLoginItem: NSMenuItem?
  private var languageAutoItem: NSMenuItem?
  private var languageEnglishItem: NSMenuItem?
  private var languageIndonesianItem: NSMenuItem?
  private var fallbackToOpenRouterItem: NSMenuItem?
  private var selectionItem: NSMenuItem?
  private var allItem: NSMenuItem?
  private var analyzeToneItem: NSMenuItem?
  private var cancelCorrectionItem: NSMenuItem?
  private var checkForUpdatesItem: NSMenuItem?
  private var updateStatusItem: NSMenuItem?
  private var updateLastCheckedItem: NSMenuItem?
  private var manualUpdateCheckInProgress = false
  private var updateFoundInCycle = false
  private var updateStatus: UpdateStatus = .unknown
  private let lastUpdateCheckKey = "lastUpdateCheckDate"
  private lazy var updateDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()

  private let keychainAccountGemini = "geminiApiKey"
  private let keychainAccountOpenRouter = "openRouterApiKey"
  private let keychainAccountOpenAI = "openAIApiKey"
  private let keychainAccountAnthropic = "anthropicApiKey"
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let expectedBundleIdentifier = "com.kxxil01.TextPolish"
  private var keychainService: String {
    Bundle.main.bundleIdentifier ?? expectedBundleIdentifier
  }

  private let didShowWelcomeKey = "didShowWelcome_0_1"
  private let expectedAppName = "TextPolish"

  private let correctionCountKey = "correctionCount"
  private let correctionCountDateKey = "correctionCountDate"
  private var todayCorrectionCount: Int = 0

  private let toneAnalysisCountKey = "toneAnalysisCount"
  private let toneAnalysisCountDateKey = "toneAnalysisCountDate"
  private var todayToneAnalysisCount: Int = 0

  private var appDisplayName: String {
    let display =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
      expectedAppName
    let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? expectedAppName : trimmed
  }

  private var isUpdaterAvailable: Bool {
    let feedURL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? ""
    let publicKey = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? ""
    return !feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    baseImage = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: appDisplayName)
    loadTodayCorrectionCount()
    loadTodayToneAnalysisCount()
    let initialIcon = makeIconWithBadge(count: todayCorrectionCount + todayToneAnalysisCount)
    statusItem.button?.image = initialIcon
    statusItem.button?.toolTip = appDisplayName
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusItemClicked(_:))
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

    let feedback = StatusItemFeedback(statusItem: statusItem, baseImage: initialIcon)
    self.feedback = feedback
    correctionController = CorrectionController(
      corrector: CorrectorFactory.make(settings: settings),
      feedback: feedback,
      settings: settings,
      timings: .init(settings: settings),
      recoverer: { [weak self] error in
        guard let self else { return nil }
        return await self.recoverFromError(error)
      },
      shouldAttemptFallback: { [weak self] error in
        guard let self else { return false }
        return self.shouldAttemptFallback(for: error)
      },
      onSuccess: { [weak self] in
        self?.incrementCorrectionCount()
      }
    )

    let toneResultWindow = ToneAnalysisResultWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    self.toneResultWindow = toneResultWindow
    toneAnalysisController = ToneAnalysisController(
      analyzer: ToneAnalyzerFactory.make(settings: settings),
      feedback: feedback,
      resultPresenter: toneResultWindow,
      timings: .init(settings: settings),
      onSuccess: { [weak self] in
        self?.incrementToneAnalysisCount()
      }
    )

    workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
      guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
      Task { @MainActor [weak self] in
        self?.lastTargetApplication = app
      }
    }

    // Listen for settings changes
    NotificationCenter.default.addObserver(
      forName: .settingsDidChange,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let newSettings = notification.object as? Settings else { return }
      Task { @MainActor [weak self] in
        self?.settings = newSettings
        self?.refreshCorrector()
        self?.setupHotKeys()
      }
    }

    setupMenu()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(diagnosticsDidUpdate),
      name: .diagnosticsUpdated,
      object: nil
    )
    setupHotKeys()
    _ = updaterController
    if isUpdaterAvailable {
      updaterController.updater.automaticallyChecksForUpdates = true
      NSLog("[TextPolish] Auto-update enabled, interval: \(updaterController.updater.updateCheckInterval)s")
    } else {
      updaterController.updater.automaticallyChecksForUpdates = false
      NSLog("[TextPolish] Auto-update disabled (missing SUFeedURL or SUPublicEDKey)")
    }
    maybeShowWelcome()
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    captureFrontmostApplication()
    refreshCorrectionCountIfNewDay()
    refreshToneAnalysisCountIfNewDay()
    updateStatusItemIcon()
    syncLaunchAtLoginMenuState()
    syncUpdateMenuItems()
    guard let statusMenu, let button = statusItem.button else { return }
    button.highlight(true)
    statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    button.highlight(false)
  }

  @objc private func diagnosticsDidUpdate() {
    syncProviderHealthItem()
    diagnosticsWindow?.update(with: DiagnosticsStore.shared.lastSnapshot)
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    guard isUpdaterAvailable else {
      feedback?.showError("Updates are not configured for this build.")
      return
    }
    if manualUpdateCheckInProgress {
      feedback?.showInfo("Update check already running.")
      return
    }
    manualUpdateCheckInProgress = true
    updateFoundInCycle = false
    updateStatus = .checking
    syncUpdateMenuItems()
    feedback?.showInfo("Checking for updates...")
    NSApp.activate(ignoringOtherApps: true)
    updaterController.checkForUpdates(sender)
  }

  private func resetManualUpdateCheckState() {
    manualUpdateCheckInProgress = false
    updateFoundInCycle = false
  }

  private func finishManualUpdateCheck(with feedback: UpdateCheckFeedback?) {
    resetManualUpdateCheckState()
    syncUpdateMenuItems()
    guard let feedback else { return }
    switch feedback.kind {
    case .info:
      self.feedback?.showInfo(feedback.message)
    case .error:
      self.feedback?.showError(feedback.message)
    }
  }

  private func captureFrontmostApplication() {
    guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
    guard frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
    lastTargetApplication = frontmost
  }

  private func setupMenu() {
    let menu = NSMenu()
    menu.delegate = self

    let selectionItem = NSMenuItem(
      title: "Correct Selection",
      action: #selector(correctSelection),
      keyEquivalent: ""
    )
    selectionItem.target = self

    let allItem = NSMenuItem(
      title: "Correct All",
      action: #selector(correctAll),
      keyEquivalent: ""
    )
    allItem.target = self

    let analyzeToneItem = NSMenuItem(
      title: "Analyze Tone",
      action: #selector(analyzeTone),
      keyEquivalent: ""
    )
    analyzeToneItem.target = self

    self.selectionItem = selectionItem
    self.allItem = allItem
    self.analyzeToneItem = analyzeToneItem

    menu.addItem(selectionItem)
    menu.addItem(allItem)
    menu.addItem(analyzeToneItem)

    let cancelItem = NSMenuItem(
      title: "Cancel Correction",
      action: #selector(cancelCorrection),
      keyEquivalent: ""
    )
    cancelItem.target = self
    self.cancelCorrectionItem = cancelItem
    menu.addItem(cancelItem)
    menu.addItem(.separator())

    let hotKeysItem = NSMenuItem(title: "Hotkeys", action: nil, keyEquivalent: "")
    let hotKeysMenu = NSMenu()

    let setSelectionHotKeyItem = NSMenuItem(
      title: "Set Correct Selection Hotkey…",
      action: #selector(setCorrectSelectionHotKey),
      keyEquivalent: ""
    )
    setSelectionHotKeyItem.target = self

    let setAllHotKeyItem = NSMenuItem(
      title: "Set Correct All Hotkey…",
      action: #selector(setCorrectAllHotKey),
      keyEquivalent: ""
    )
    setAllHotKeyItem.target = self

    let setAnalyzeToneHotKeyItem = NSMenuItem(
      title: "Set Analyze Tone Hotkey…",
      action: #selector(setAnalyzeToneHotKey),
      keyEquivalent: ""
    )
    setAnalyzeToneHotKeyItem.target = self

    let resetHotKeysItem = NSMenuItem(
      title: "Reset to Defaults",
      action: #selector(resetHotKeys),
      keyEquivalent: ""
    )
    resetHotKeysItem.target = self

    hotKeysMenu.addItem(setSelectionHotKeyItem)
    hotKeysMenu.addItem(setAllHotKeyItem)
    hotKeysMenu.addItem(setAnalyzeToneHotKeyItem)
    hotKeysMenu.addItem(.separator())
    hotKeysMenu.addItem(resetHotKeysItem)

    hotKeysItem.submenu = hotKeysMenu
    menu.addItem(hotKeysItem)
    menu.addItem(.separator())

    let providerItem = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
    let providerMenu = NSMenu()

    let geminiItem = NSMenuItem(
      title: "Gemini",
      action: #selector(selectGeminiProvider),
      keyEquivalent: ""
    )
    geminiItem.target = self

    let openRouterItem = NSMenuItem(
      title: "OpenRouter",
      action: #selector(selectOpenRouterProvider),
      keyEquivalent: ""
    )
    openRouterItem.target = self

    let openAIItem = NSMenuItem(
      title: "OpenAI",
      action: #selector(selectOpenAIProvider),
      keyEquivalent: ""
    )
    openAIItem.target = self

    let anthropicItem = NSMenuItem(
      title: "Anthropic",
      action: #selector(selectAnthropicProvider),
      keyEquivalent: ""
    )
    anthropicItem.target = self

    providerGeminiItem = geminiItem
    providerOpenRouterItem = openRouterItem
    providerOpenAIItem = openAIItem
    providerAnthropicItem = anthropicItem
    syncProviderMenuStates()

    providerMenu.addItem(geminiItem)
    providerMenu.addItem(openRouterItem)
    providerMenu.addItem(openAIItem)
    providerMenu.addItem(anthropicItem)
    providerMenu.addItem(.separator())

    let providerHealthItem = NSMenuItem(
      title: "Health: Unknown",
      action: nil,
      keyEquivalent: ""
    )
    providerHealthItem.isEnabled = false
    self.providerHealthItem = providerHealthItem
    providerMenu.addItem(providerHealthItem)
    providerMenu.addItem(.separator())

    let setGeminiKeyItem = NSMenuItem(
      title: "Set Gemini API Key…",
      action: #selector(setGeminiApiKey),
      keyEquivalent: ""
    )
    setGeminiKeyItem.target = self

    let setGeminiModelItem = NSMenuItem(
      title: "Set Gemini Model…",
      action: #selector(setGeminiModel),
      keyEquivalent: ""
    )
    setGeminiModelItem.target = self

    let detectGeminiModelItem = NSMenuItem(
      title: "Detect Gemini Model…",
      action: #selector(detectGeminiModel),
      keyEquivalent: ""
    )
    detectGeminiModelItem.target = self

    let setOpenRouterKeyItem = NSMenuItem(
      title: "Set OpenRouter API Key…",
      action: #selector(setOpenRouterApiKey),
      keyEquivalent: ""
    )
    setOpenRouterKeyItem.target = self

    let setOpenRouterModelItem = NSMenuItem(
      title: "Set OpenRouter Model…",
      action: #selector(setOpenRouterModel),
      keyEquivalent: ""
    )
    setOpenRouterModelItem.target = self

    let detectOpenRouterModelItem = NSMenuItem(
      title: "Detect OpenRouter Model…",
      action: #selector(detectOpenRouterModel),
      keyEquivalent: ""
    )
    detectOpenRouterModelItem.target = self

    let setOpenAIKeyItem = NSMenuItem(
      title: "Set OpenAI API Key…",
      action: #selector(setOpenAIApiKey),
      keyEquivalent: ""
    )
    setOpenAIKeyItem.target = self

    let setOpenAIModelItem = NSMenuItem(
      title: "Set OpenAI Model…",
      action: #selector(setOpenAIModel),
      keyEquivalent: ""
    )
    setOpenAIModelItem.target = self

    let setAnthropicKeyItem = NSMenuItem(
      title: "Set Anthropic API Key…",
      action: #selector(setAnthropicApiKey),
      keyEquivalent: ""
    )
    setAnthropicKeyItem.target = self

    let setAnthropicModelItem = NSMenuItem(
      title: "Set Anthropic Model…",
      action: #selector(setAnthropicModel),
      keyEquivalent: ""
    )
    setAnthropicModelItem.target = self

    self.setGeminiKeyItem = setGeminiKeyItem
    self.setGeminiModelItem = setGeminiModelItem
    self.detectGeminiModelItem = detectGeminiModelItem
    self.setOpenRouterKeyItem = setOpenRouterKeyItem
    self.setOpenRouterModelItem = setOpenRouterModelItem
    self.detectOpenRouterModelItem = detectOpenRouterModelItem
    self.setOpenAIKeyItem = setOpenAIKeyItem
    self.setOpenAIModelItem = setOpenAIModelItem
    self.setAnthropicKeyItem = setAnthropicKeyItem
    self.setAnthropicModelItem = setAnthropicModelItem

    providerMenu.addItem(setGeminiKeyItem)
    providerMenu.addItem(setGeminiModelItem)
    providerMenu.addItem(detectGeminiModelItem)
    providerMenu.addItem(setOpenRouterKeyItem)
    providerMenu.addItem(setOpenRouterModelItem)
    providerMenu.addItem(detectOpenRouterModelItem)
    providerMenu.addItem(setOpenAIKeyItem)
    providerMenu.addItem(setOpenAIModelItem)
    providerMenu.addItem(setAnthropicKeyItem)
    providerMenu.addItem(setAnthropicModelItem)

    providerItem.submenu = providerMenu
    menu.addItem(providerItem)

    let preferencesItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
    let preferencesMenu = NSMenu()

    let launchAtLoginItem = NSMenuItem(
      title: "Start at Login",
      action: #selector(toggleLaunchAtLogin),
      keyEquivalent: ""
    )
    launchAtLoginItem.target = self
    self.launchAtLoginItem = launchAtLoginItem
    preferencesMenu.addItem(launchAtLoginItem)

    let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
    let languageMenu = NSMenu()

    let languageAutoItem = NSMenuItem(
      title: Settings.CorrectionLanguage.auto.displayName,
      action: #selector(selectLanguageAuto),
      keyEquivalent: ""
    )
    languageAutoItem.target = self

    let languageEnglishItem = NSMenuItem(
      title: Settings.CorrectionLanguage.englishUS.displayName,
      action: #selector(selectLanguageEnglish),
      keyEquivalent: ""
    )
    languageEnglishItem.target = self

    let languageIndonesianItem = NSMenuItem(
      title: Settings.CorrectionLanguage.indonesian.displayName,
      action: #selector(selectLanguageIndonesian),
      keyEquivalent: ""
    )
    languageIndonesianItem.target = self

    self.languageAutoItem = languageAutoItem
    self.languageEnglishItem = languageEnglishItem
    self.languageIndonesianItem = languageIndonesianItem

    languageMenu.addItem(languageAutoItem)
    languageMenu.addItem(languageEnglishItem)
    languageMenu.addItem(languageIndonesianItem)

    languageItem.submenu = languageMenu
    preferencesMenu.addItem(languageItem)

    let fallbackToOpenRouterItem = NSMenuItem(
      title: "Fallback to alternate provider on errors",
      action: #selector(toggleFallbackToOpenRouter),
      keyEquivalent: ""
    )
    fallbackToOpenRouterItem.target = self
    self.fallbackToOpenRouterItem = fallbackToOpenRouterItem
    preferencesMenu.addItem(fallbackToOpenRouterItem)

    let accessibilityItem = NSMenuItem(
      title: "Open Accessibility Settings…",
      action: #selector(openAccessibilitySettings),
      keyEquivalent: ""
    )
    accessibilityItem.target = self
    preferencesMenu.addItem(accessibilityItem)

    let openSettingsItem = NSMenuItem(
      title: "Open Settings Window…",
      action: #selector(openSettingsWindow),
      keyEquivalent: ""
    )
    openSettingsItem.target = self
    preferencesMenu.addItem(openSettingsItem)

    preferencesItem.submenu = preferencesMenu
    menu.addItem(preferencesItem)

    let diagnosticsItem = NSMenuItem(
      title: "Diagnostics…",
      action: #selector(openDiagnostics),
      keyEquivalent: ""
    )
    diagnosticsItem.target = self
    menu.addItem(diagnosticsItem)

    let aboutItem = NSMenuItem(
      title: "About & Privacy",
      action: #selector(showAboutAndPrivacy),
      keyEquivalent: ""
    )
    aboutItem.target = self
    menu.addItem(aboutItem)

    let updatesItem = NSMenuItem(title: "Check for Updates", action: nil, keyEquivalent: "")
    let updatesMenu = NSMenu()

    let checkForUpdatesItem = NSMenuItem(
      title: "Check",
      action: #selector(checkForUpdates),
      keyEquivalent: ""
    )
    checkForUpdatesItem.target = self
    self.checkForUpdatesItem = checkForUpdatesItem
    updatesMenu.addItem(checkForUpdatesItem)

    let updateStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    updateStatusItem.isEnabled = false
    self.updateStatusItem = updateStatusItem
    updatesMenu.addItem(updateStatusItem)

    let updateLastCheckedItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    updateLastCheckedItem.isEnabled = false
    self.updateLastCheckedItem = updateLastCheckedItem
    updatesMenu.addItem(updateLastCheckedItem)

    updatesItem.submenu = updatesMenu
    menu.addItem(updatesItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    quitItem.keyEquivalentModifierMask = [.command]
    menu.addItem(quitItem)

    statusMenu = menu
    syncLaunchAtLoginMenuState()
    syncFallbackMenuState()
    syncProviderMenuStates()
    syncProviderHealthItem()
    syncLanguageMenuState()
    syncHotKeyMenuItems()
    syncCancelMenuState()
    syncUpdateMenuItems()
  }

  func menuWillOpen(_ menu: NSMenu) {
    isMenuOpen = true
    syncCancelMenuState()
    syncProviderHealthItem()
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
    guard let action = pendingAfterMenuAction else { return }
    pendingAfterMenuAction = nil
    Task { @MainActor in
      await action()
    }
  }

  private func syncProviderMenuStates() {
    providerGeminiItem?.state = settings.provider == .gemini ? .on : .off
    providerOpenRouterItem?.state = settings.provider == .openRouter ? .on : .off
    providerOpenAIItem?.state = settings.provider == .openAI ? .on : .off
    providerAnthropicItem?.state = settings.provider == .anthropic ? .on : .off
    setGeminiKeyItem?.isEnabled = settings.provider == .gemini
    setGeminiModelItem?.isEnabled = settings.provider == .gemini
    detectGeminiModelItem?.isEnabled = settings.provider == .gemini
    setOpenRouterKeyItem?.isEnabled = settings.provider == .openRouter
    setOpenRouterModelItem?.isEnabled = settings.provider == .openRouter
    detectOpenRouterModelItem?.isEnabled = settings.provider == .openRouter
    setOpenAIKeyItem?.isEnabled = settings.provider == .openAI
    setOpenAIModelItem?.isEnabled = settings.provider == .openAI
    setAnthropicKeyItem?.isEnabled = settings.provider == .anthropic
    setAnthropicModelItem?.isEnabled = settings.provider == .anthropic
    if settings.provider == .gemini {
      statusItem.button?.toolTip = "\(appDisplayName) (Gemini: \(settings.geminiModel))"
    } else if settings.provider == .openRouter {
      statusItem.button?.toolTip = "\(appDisplayName) (OpenRouter: \(settings.openRouterModel))"
    } else if settings.provider == .openAI {
      statusItem.button?.toolTip = "\(appDisplayName) (OpenAI: \(settings.openAIModel))"
    } else if settings.provider == .anthropic {
      statusItem.button?.toolTip = "\(appDisplayName) (Anthropic: \(settings.anthropicModel))"
    } else {
      statusItem.button?.toolTip = appDisplayName
    }
  }

  private func syncProviderHealthItem() {
    guard let providerHealthItem else { return }
    providerHealthItem.title = DiagnosticsStore.shared.healthMenuTitle()
    providerHealthItem.toolTip = DiagnosticsStore.shared.healthToolTip()
  }

  private func syncLaunchAtLoginMenuState() {
    guard let launchAtLoginItem else { return }

    switch SMAppService.mainApp.status {
    case .enabled:
      launchAtLoginItem.state = .on
      launchAtLoginItem.toolTip = nil
    case .requiresApproval:
      launchAtLoginItem.state = .mixed
      launchAtLoginItem.toolTip = "Requires approval in System Settings → General → Login Items"
    default:
      launchAtLoginItem.state = .off
      launchAtLoginItem.toolTip = isRunningFromApplicationsFolder() ? nil : "Move the app to /Applications to enable Start at Login reliably"
    }
  }

  private func syncFallbackMenuState() {
    fallbackToOpenRouterItem?.state = settings.enableGeminiOpenRouterFallback ? .on : .off
  }

  private func syncLanguageMenuState() {
    languageAutoItem?.state = settings.correctionLanguage == .auto ? .on : .off
    languageEnglishItem?.state = settings.correctionLanguage == .englishUS ? .on : .off
    languageIndonesianItem?.state = settings.correctionLanguage == .indonesian ? .on : .off
  }

  private func syncUpdateMenuItems() {
    let effectiveStatus: UpdateStatus = isUpdaterAvailable ? updateStatus : .message("Updates not configured")
    updateStatusItem?.title = effectiveStatus.menuTitle
    updateLastCheckedItem?.title = updateLastCheckedTitle()
    if !isUpdaterAvailable {
      checkForUpdatesItem?.isEnabled = false
      checkForUpdatesItem?.toolTip = "Updates are not configured for this build."
    } else if manualUpdateCheckInProgress {
      checkForUpdatesItem?.isEnabled = false
      checkForUpdatesItem?.toolTip = "Update check in progress."
    } else {
      checkForUpdatesItem?.isEnabled = true
      checkForUpdatesItem?.toolTip = nil
    }
  }

  private func updateLastCheckedTitle() -> String {
    guard isUpdaterAvailable else { return "Last checked: Not available" }
    guard let date = lastUpdateCheckDate() else { return "Last checked: Never" }
    return "Last checked: \(updateDateFormatter.string(from: date))"
  }

  private func lastUpdateCheckDate() -> Date? {
    UserDefaults.standard.object(forKey: lastUpdateCheckKey) as? Date
  }

  private func recordLastUpdateCheck(_ date: Date = Date()) {
    UserDefaults.standard.set(date, forKey: lastUpdateCheckKey)
  }

  private func persistSettings() {
    do {
      try Settings.save(settings)
    } catch {
      NSLog("[TextPolish] Failed to save settings: \(error)")
    }
  }

  // MARK: - Correction Counter & Badge

  private func loadTodayCorrectionCount() {
    refreshCorrectionCountIfNewDay()
  }

  private func refreshCorrectionCountIfNewDay() {
    let defaults = UserDefaults.standard
    let storedDate = defaults.string(forKey: correctionCountDateKey) ?? ""
    let today = formattedToday()

    if storedDate == today {
      todayCorrectionCount = defaults.integer(forKey: correctionCountKey)
    } else {
      todayCorrectionCount = 0
      defaults.set(0, forKey: correctionCountKey)
      defaults.set(today, forKey: correctionCountDateKey)
    }
  }

  private func incrementCorrectionCount() {
    refreshCorrectionCountIfNewDay()
    todayCorrectionCount += 1
    UserDefaults.standard.set(todayCorrectionCount, forKey: correctionCountKey)
    updateStatusItemIcon()
  }

  private func loadTodayToneAnalysisCount() {
    refreshToneAnalysisCountIfNewDay()
  }

  private func refreshToneAnalysisCountIfNewDay() {
    let defaults = UserDefaults.standard
    let storedDate = defaults.string(forKey: toneAnalysisCountDateKey) ?? ""
    let today = formattedToday()

    if storedDate == today {
      todayToneAnalysisCount = defaults.integer(forKey: toneAnalysisCountKey)
    } else {
      todayToneAnalysisCount = 0
      defaults.set(0, forKey: toneAnalysisCountKey)
      defaults.set(today, forKey: toneAnalysisCountDateKey)
    }
  }

  private func incrementToneAnalysisCount() {
    refreshToneAnalysisCountIfNewDay()
    todayToneAnalysisCount += 1
    UserDefaults.standard.set(todayToneAnalysisCount, forKey: toneAnalysisCountKey)
    updateStatusItemIcon()
  }

  private func formattedToday() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }

  private func updateStatusItemIcon() {
    let icon = makeIconWithBadge(count: todayCorrectionCount + todayToneAnalysisCount)
    statusItem.button?.image = icon
    feedback?.updateBaseImage(icon)
  }

  private func makeIconWithBadge(count: Int) -> NSImage? {
    guard let base = baseImage else { return nil }
    let size = NSSize(width: 18, height: 18)

    // When count == 0, return template image (adapts to menu bar)
    if count == 0 {
      let image = NSImage(size: size, flipped: false) { rect in
        base.draw(in: rect)
        return true
      }
      image.isTemplate = true
      return image
    }

    // When count > 0, draw tinted icon with badge
    let image = NSImage(size: size, flipped: false) { rect in
      // Draw base icon tinted to menu bar foreground color
      let tintedBase = base.copy() as! NSImage
      tintedBase.lockFocus()
      NSColor.white.set()
      let imageRect = NSRect(origin: .zero, size: tintedBase.size)
      imageRect.fill(using: .sourceAtop)
      tintedBase.unlockFocus()
      tintedBase.draw(in: rect)

      // Draw badge circle
      let badgeSize: CGFloat = 10
      let badgeRect = NSRect(
        x: rect.width - badgeSize + 2,
        y: rect.height - badgeSize + 2,
        width: badgeSize,
        height: badgeSize
      )

      NSColor.systemRed.setFill()
      NSBezierPath(ovalIn: badgeRect).fill()

      // Draw badge text
      let text = count > 99 ? "99+" : "\(count)"
      let font = NSFont.systemFont(ofSize: 7, weight: .bold)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
      ]
      let textSize = text.size(withAttributes: attrs)
      let textRect = NSRect(
        x: badgeRect.midX - textSize.width / 2,
        y: badgeRect.midY - textSize.height / 2,
        width: textSize.width,
        height: textSize.height
      )
      text.draw(in: textRect, withAttributes: attrs)

      return true
    }

    image.isTemplate = false
    return image
  }

  private func keychainLabel(for account: String) -> String? {
    switch account {
    case keychainAccountGemini:
      return "\(expectedAppName) — Gemini API Key"
    case keychainAccountOpenRouter:
      return "\(expectedAppName) — OpenRouter API Key"
    case keychainAccountOpenAI:
      return "\(expectedAppName) — OpenAI API Key"
    case keychainAccountAnthropic:
      return "\(expectedAppName) — Anthropic API Key"
    default:
      return "\(expectedAppName) — Secret"
    }
  }

  private func setKeychainPassword(_ password: String, service: String, account: String) async throws {
    NSLog("[TextPolish] Keychain set start account=\(account)")
    NSApp.activate(ignoringOtherApps: true)
    let label = keychainLabel(for: account)
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try Keychain.setPassword(password, service: service, account: account, label: label)
          NSLog("[TextPolish] Keychain set success account=\(account)")
          continuation.resume()
        } catch {
          NSLog("[TextPolish] Keychain set failed account=\(account) error=\(error)")
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func deleteKeychainPassword(service: String, account: String) async throws {
    NSLog("[TextPolish] Keychain delete start account=\(account)")
    NSApp.activate(ignoringOtherApps: true)
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try Keychain.deletePassword(service: service, account: account)
          NSLog("[TextPolish] Keychain delete success account=\(account)")
          continuation.resume()
        } catch {
          NSLog("[TextPolish] Keychain delete failed account=\(account) error=\(error)")
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func refreshCorrector() {
    correctionController?.updateSettings(settings)
    correctionController?.updateCorrector(CorrectorFactory.make(settings: settings))
    correctionController?.updateTimings(.init(settings: settings))
    toneAnalysisController?.updateAnalyzer(ToneAnalyzerFactory.make(settings: settings))
    toneAnalysisController?.updateTimings(.init(settings: settings))
  }

  private func timingsOverride(for app: NSRunningApplication?) -> CorrectionController.Timings? {
    guard let profile = settings.timingProfile(
      bundleIdentifier: app?.bundleIdentifier,
      appName: app?.localizedName
    ) else {
      return nil
    }
    let baseTimings = CorrectionController.Timings(settings: settings)
    return baseTimings.applying(profile)
  }

  private func runAfterMenuDismissed(_ action: @escaping @MainActor () async -> Void) {
    if isMenuOpen {
      pendingAfterMenuAction = action
      return
    }
    Task { @MainActor in
      await action()
    }
  }

  private func normalizeGeminiModel(_ model: String) -> String {
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("models/") {
      return String(trimmed.dropFirst("models/".count))
    }
    return trimmed
  }

  private func recoverFromError(_ error: Error) async -> CorrectionController.RecoveryAction? {
    switch settings.provider {
    case .gemini:
      guard let geminiError = error as? GeminiCorrector.GeminiError else { return nil }
      if case .requestFailed(let status, _) = geminiError, status == 404 {
        guard let apiKey = currentGeminiApiKey() else { return nil }
        do {
          let models = try await fetchGeminiModels(apiKey: apiKey)
          guard let chosenRaw = chooseGeminiModel(from: models) else { return nil }
          let chosen = normalizeGeminiModel(chosenRaw)
          let current = normalizeGeminiModel(settings.geminiModel)
          guard !chosen.isEmpty, chosen != current else { return nil }

          settings.geminiModel = chosen
          persistSettings()
          syncProviderMenuStates()
          refreshCorrector()
          return CorrectionController.RecoveryAction(message: "Gemini model auto-detected: \(chosen)", corrector: nil)
        } catch {
          NSLog("[TextPolish] Auto-detect Gemini model failed: \(error)")
        }
      }

      return nil
    case .openRouter:
      guard let openRouterError = error as? OpenRouterCorrector.OpenRouterError else { return nil }

      guard case .requestFailed(let status, _) = openRouterError else { return nil }
      guard status == 404 || status == 402 else { return nil }
      let preferFree = (status == 402)
      guard let apiKey = currentOpenRouterApiKey() else { return nil }

      do {
        let current = settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let chosen = try await detectWorkingOpenRouterModel(
          apiKey: apiKey,
          preferFree: preferFree,
          preferredFirst: nil,
          excluding: current.isEmpty ? nil : current
        ) else { return nil }

        settings.openRouterModel = chosen
        persistSettings()
        syncProviderMenuStates()
        refreshCorrector()
        let message = preferFree
          ? "OpenRouter switched to a working free model: \(chosen)"
          : "OpenRouter model auto-detected: \(chosen)"
        return CorrectionController.RecoveryAction(message: message, corrector: nil)
      } catch {
        NSLog("[TextPolish] Auto-detect OpenRouter model failed: \(error)")
        return nil
      }
    case .openAI:
      return nil
    case .anthropic:
      return nil
    }
  }

  private func shouldAttemptFallback(for error: Error) -> Bool {
    guard settings.enableGeminiOpenRouterFallback else { return false }
    guard shouldFallbackFromError(error) else { return false }

    switch settings.provider {
    case .gemini:
      return currentOpenRouterApiKey() != nil
    case .openRouter:
      return currentGeminiApiKey() != nil
    case .openAI:
      return false
    case .anthropic:
      return false
    }
  }

  private func shouldFallbackFromError(_ error: Error) -> Bool {
    if let geminiError = error as? GeminiCorrector.GeminiError {
      return shouldFallbackFromGeminiError(geminiError)
    }
    if let openRouterError = error as? OpenRouterCorrector.OpenRouterError {
      return shouldFallbackFromOpenRouterError(openRouterError)
    }
    if let urlError = error as? URLError {
      return shouldFallbackFromURLError(urlError)
    }
    return false
  }

  private func shouldFallbackFromGeminiError(_ error: GeminiCorrector.GeminiError) -> Bool {
    switch error {
    case .missingApiKey, .invalidBaseURL:
      return false
    case .blocked, .emptyResponse, .overRewrite:
      // Provider returned an unusable response; fallback can still salvage the user flow.
      return true
    case .requestFailed(let status, _):
      if status == 401 || status == 403 {
        return false
      }
      if status == 429 {
        return true
      }
      if status <= 0 {
        return true
      }
      return (500...599).contains(status)
    }
  }

  private func shouldFallbackFromOpenRouterError(_ error: OpenRouterCorrector.OpenRouterError) -> Bool {
    switch error {
    case .missingApiKey, .invalidBaseURL:
      return false
    case .emptyResponse, .overRewrite:
      return true
    case .requestFailed(let status, _):
      if status == 401 || status == 403 || status == 402 {
        return false
      }
      if status == 429 {
        return true
      }
      if status <= 0 {
        return true
      }
      return (500...599).contains(status)
    }
  }

  private func shouldFallbackFromURLError(_ error: URLError) -> Bool {
    switch error.code {
    case .timedOut,
         .cannotFindHost,
         .cannotConnectToHost,
         .networkConnectionLost,
         .dnsLookupFailed,
         .notConnectedToInternet:
      return true
    default:
      return false
    }
  }

  private func setupHotKeys() {
    hotKeyManager.onHotKey = { [weak self] id in
      guard let self else { return }
      self.captureFrontmostApplication()
      let target = self.lastTargetApplication
      let timings = self.timingsOverride(for: target)
      switch id {
      case HotKeyManager.HotKeyID.correctSelection.rawValue:
        self.correctionController?.correctSelection(targetApplication: target, timingsOverride: timings)
      case HotKeyManager.HotKeyID.correctAll.rawValue:
        self.correctionController?.correctAll(targetApplication: target, timingsOverride: timings)
      case HotKeyManager.HotKeyID.analyzeTone.rawValue:
        self.toneAnalysisController?.analyzeSelection(targetApplication: target)
      default:
        break
      }
    }

    do {
      try hotKeyManager.registerHotKeys(
        correctSelection: settings.hotKeyCorrectSelection,
        correctAll: settings.hotKeyCorrectAll,
        analyzeTone: settings.hotKeyAnalyzeTone
      )
    } catch {
      NSLog("[TextPolish] Failed to register hotkeys: \(error)")
    }
  }

  @objc private func correctSelection() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let target = self.lastTargetApplication
      let timings = self.timingsOverride(for: target)
      self.correctionController?.correctSelection(targetApplication: target, timingsOverride: timings)
    }
  }

  @objc private func correctAll() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let target = self.lastTargetApplication
      let timings = self.timingsOverride(for: target)
      self.correctionController?.correctAll(targetApplication: target, timingsOverride: timings)
    }
  }

  @objc private func cancelCorrection() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      if self.correctionController?.cancelCurrentCorrection() == true {
        self.feedback?.showInfo("Canceling...")
      } else {
        self.feedback?.showInfo("No correction in progress")
      }
    }
  }

  @objc private func analyzeTone() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let target = self.lastTargetApplication
      self.toneAnalysisController?.analyzeSelection(targetApplication: target)
    }
  }

  @objc private func selectGeminiProvider() {
    settings.provider = .gemini
    persistSettings()
    syncProviderMenuStates()
    refreshCorrector()

    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountGemini))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountGemini))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasKey = !keyFromKeychain.isEmpty || !keyFromLegacyKeychain.isEmpty
    if !hasKey,
       settings.geminiApiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    {
      setGeminiApiKey()
    }
  }

  @objc private func selectOpenRouterProvider() {
    settings.provider = .openRouter
    persistSettings()
    syncProviderMenuStates()
    refreshCorrector()

    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountOpenRouter))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountOpenRouter))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasKey = !keyFromKeychain.isEmpty || !keyFromLegacyKeychain.isEmpty
    if !hasKey,
       settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    {
      setOpenRouterApiKey()
    }
  }

  @objc private func selectOpenAIProvider() {
    settings.provider = .openAI
    persistSettings()
    syncProviderMenuStates()
    refreshCorrector()

    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountOpenAI))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountOpenAI))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasKey = !keyFromKeychain.isEmpty || !keyFromLegacyKeychain.isEmpty
    if !hasKey,
       settings.openAIApiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    {
      setOpenAIApiKey()
    }
  }

  @objc private func selectAnthropicProvider() {
    settings.provider = .anthropic
    persistSettings()
    syncProviderMenuStates()
    refreshCorrector()

    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountAnthropic))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountAnthropic))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasKey = !keyFromKeychain.isEmpty || !keyFromLegacyKeychain.isEmpty
    if !hasKey,
       settings.anthropicApiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    {
      setAnthropicApiKey()
    }
  }

  @objc private func setGeminiApiKey() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let result = self.promptForApiKey(
        title: "Gemini API Key",
        message: "Stored securely in Keychain. Key is visible while editing; it is stored securely. Leave blank and click Clear to remove."
      )
      NSLog("[TextPolish] Gemini key prompt result=\(self.apiKeyPromptResultKind(result))")

      switch result {
      case .canceled:
        return
      case .clear:
        self.feedback?.showInfo("Clearing Gemini key…")
        do {
          try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountGemini)
          if self.legacyKeychainService != self.keychainService {
            try? await self.deleteKeychainPassword(service: self.legacyKeychainService, account: self.keychainAccountGemini)
          }
          self.settings.geminiApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("Gemini key cleared")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to clear key: \(error)")
          self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
        }
      case .save(let value):
        self.feedback?.showInfo("Saving Gemini key… (check for a Keychain prompt)")
        do {
          try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountGemini)
          self.settings.geminiApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("Gemini key saved")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to save key: \(error)")
          self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
        }
      }
    }
  }

  @objc private func setOpenRouterApiKey() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let result = self.promptForApiKey(
        title: "OpenRouter API Key",
        message: "Stored securely in Keychain. Key is visible while editing; it is stored securely. Leave blank and click Clear to remove."
      )
      NSLog("[TextPolish] OpenRouter key prompt result=\(self.apiKeyPromptResultKind(result))")

      switch result {
      case .canceled:
        return
      case .clear:
        self.feedback?.showInfo("Clearing OpenRouter key…")
        do {
          try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountOpenRouter)
          if self.legacyKeychainService != self.keychainService {
            try? await self.deleteKeychainPassword(service: self.legacyKeychainService, account: self.keychainAccountOpenRouter)
          }
          self.settings.openRouterApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("OpenRouter key cleared")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to clear key: \(error)")
          self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
        }
      case .save(let value):
        self.feedback?.showInfo("Saving OpenRouter key… (check for a Keychain prompt)")
        do {
          try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountOpenRouter)
          self.settings.openRouterApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("OpenRouter key saved")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to save key: \(error)")
          self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
        }
      }
    }
  }

  @objc private func setOpenAIApiKey() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let result = self.promptForApiKey(
        title: "OpenAI API Key",
        message: "Stored securely in Keychain. Key is visible while editing; it is stored securely. Leave blank and click Clear to remove."
      )
      NSLog("[TextPolish] OpenAI key prompt completed")

      switch result {
      case .canceled:
        return
      case .clear:
        self.feedback?.showInfo("Clearing OpenAI key…")
        do {
          try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountOpenAI)
          if self.legacyKeychainService != self.keychainService {
            try? await self.deleteKeychainPassword(service: self.legacyKeychainService, account: self.keychainAccountOpenAI)
          }
          self.settings.openAIApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("OpenAI key cleared")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to clear key: \(error)")
          self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
        }
      case .save(let value):
        self.feedback?.showInfo("Saving OpenAI key… (check for a Keychain prompt)")
        do {
          try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountOpenAI)
          self.settings.openAIApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("OpenAI key saved")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to save key: \(error)")
          self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
        }
      }
    }
  }

  @objc private func setAnthropicApiKey() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let result = self.promptForApiKey(
        title: "Anthropic API Key",
        message: "Stored securely in Keychain. Key is visible while editing; it is stored securely. Leave blank and click Clear to remove."
      )
      NSLog("[TextPolish] Anthropic key prompt completed")

      switch result {
      case .canceled:
        return
      case .clear:
        self.feedback?.showInfo("Clearing Anthropic key…")
        do {
          try await self.deleteKeychainPassword(service: self.keychainService, account: self.keychainAccountAnthropic)
          if self.legacyKeychainService != self.keychainService {
            try? await self.deleteKeychainPassword(service: self.legacyKeychainService, account: self.keychainAccountAnthropic)
          }
          self.settings.anthropicApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("Anthropic key cleared")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to clear key: \(error)")
          self.showSimpleAlert(title: "Failed to Clear", message: "Could not remove the API key from Keychain. \(error)")
        }
      case .save(let value):
        self.feedback?.showInfo("Saving Anthropic key… (check for a Keychain prompt)")
        do {
          try await self.setKeychainPassword(value, service: self.keychainService, account: self.keychainAccountAnthropic)
          self.settings.anthropicApiKey = nil
          self.persistSettings()
          self.syncProviderMenuStates()
          self.feedback?.showInfo("Anthropic key saved")
          self.refreshCorrector()
        } catch {
          NSLog("[TextPolish] Failed to save key: \(error)")
          self.showSimpleAlert(title: "Failed to Save", message: "Could not save the API key to Keychain. \(error)")
        }
      }
    }
  }

  @objc private func setGeminiModel() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let value = self.promptForText(
        title: "Gemini Model",
        message: "Examples: gemini-2.0-flash-lite-001, gemini-2.0-flash (depends on your API key).",
        placeholder: "Model name",
        initialValue: self.settings.geminiModel
      )
      guard let value, !value.isEmpty else { return }
      let normalized = self.normalizeGeminiModel(value)
      guard !normalized.isEmpty else { return }
      self.settings.geminiModel = normalized
      self.persistSettings()
      self.syncProviderMenuStates()
      self.refreshCorrector()
    }
  }

  @objc private func setOpenRouterModel() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let value = self.promptForText(
        title: "OpenRouter Model",
        message: "Examples: google/gemini-2.0-flash-lite-001, openai/gpt-4o-mini (depends on your OpenRouter account).",
        placeholder: "Model id",
        initialValue: self.settings.openRouterModel
      )
      guard let value, !value.isEmpty else { return }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      self.settings.openRouterModel = trimmed
      self.persistSettings()
      self.syncProviderMenuStates()
      self.refreshCorrector()
    }
  }

  @objc private func setOpenAIModel() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let value = self.promptForText(
        title: "OpenAI Model",
        message: "Examples: gpt-4o-mini, gpt-4o (depends on your OpenAI account).",
        placeholder: "Model name",
        initialValue: self.settings.openAIModel
      )
      guard let value, !value.isEmpty else { return }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      self.settings.openAIModel = trimmed
      self.persistSettings()
      self.syncProviderMenuStates()
      self.refreshCorrector()
    }
  }

  @objc private func setAnthropicModel() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let value = self.promptForText(
        title: "Anthropic Model",
        message: "Examples: claude-3-5-haiku-20241022, claude-3-5-sonnet-20241022 (depends on your Anthropic account).",
        placeholder: "Model name",
        initialValue: self.settings.anthropicModel
      )
      guard let value, !value.isEmpty else { return }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      self.settings.anthropicModel = trimmed
      self.persistSettings()
      self.syncProviderMenuStates()
      self.refreshCorrector()
    }
  }

  @objc private func detectGeminiModel() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      await self.detectGeminiModelAsync()
    }
  }

  @objc private func detectOpenRouterModel() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      await self.detectOpenRouterModelAsync()
    }
  }

  @objc private func toggleLaunchAtLogin() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      do {
        let service = SMAppService.mainApp
        if service.status == .enabled {
          try service.unregister()
        } else {
          guard self.isRunningFromApplicationsFolder() else {
            self.showStartAtLoginRequiresApplications()
            self.syncLaunchAtLoginMenuState()
            return
          }
          try service.register()
        }

        self.syncLaunchAtLoginMenuState()

        if service.status == .requiresApproval {
          self.showSimpleAlert(
            title: "Approval Required",
            message: "Enable \(self.appDisplayName) in System Settings → General → Login Items."
          )
        }
      } catch {
        let message =
          (error as? LocalizedError)?.errorDescription ??
          (error as NSError).localizedDescription
        self.showSimpleAlert(title: "Start at Login Failed", message: message)
        self.syncLaunchAtLoginMenuState()
      }
    }
  }

  @objc private func toggleFallbackToOpenRouter() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      self.settings.enableGeminiOpenRouterFallback.toggle()
      self.persistSettings()
      self.syncFallbackMenuState()
    }
  }

  @objc private func selectLanguageAuto() {
    runAfterMenuDismissed { [weak self] in
      self?.setCorrectionLanguage(.auto)
    }
  }

  @objc private func selectLanguageEnglish() {
    runAfterMenuDismissed { [weak self] in
      self?.setCorrectionLanguage(.englishUS)
    }
  }

  @objc private func selectLanguageIndonesian() {
    runAfterMenuDismissed { [weak self] in
      self?.setCorrectionLanguage(.indonesian)
    }
  }

  @objc private func openSettingsWindow(_ sender: Any?) {
    settingsWindowController = SettingsWindowController()
    settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openDiagnostics() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      if self.diagnosticsWindow == nil {
        self.diagnosticsWindow = DiagnosticsWindow()
      }
      self.diagnosticsWindow?.onRunDiagnostic = { [weak self] in
        guard let self else { return }
        Task { @MainActor in
          await self.runActiveDiagnostic()
        }
      }
      self.diagnosticsWindow?.show()
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private func runActiveDiagnostic() async {
    diagnosticsWindow?.showRunning()
    let provider = settings.provider
    var lines: [String] = []
    lines.append("Provider: \(providerDisplayName(provider))")
    lines.append("─────────────────────────────────")

    switch provider {
    case .gemini:
      lines.append(contentsOf: await diagnoseGemini())
    case .openRouter:
      lines.append(contentsOf: await diagnoseOpenRouter())
    case .openAI:
      lines.append(contentsOf: await diagnoseOpenAI())
    case .anthropic:
      lines.append(contentsOf: await diagnoseAnthropic())
    }

    let result = lines.joined(separator: "\n")
    diagnosticsWindow?.showResult(result)
  }

  private func providerDisplayName(_ provider: Settings.Provider) -> String {
    switch provider {
    case .gemini: return "Gemini"
    case .openRouter: return "OpenRouter"
    case .openAI: return "OpenAI"
    case .anthropic: return "Anthropic"
    }
  }

  private func diagnoseGemini() async -> [String] {
    var lines: [String] = []
    guard let apiKey = currentGeminiApiKey(), !apiKey.isEmpty else {
      lines.append("API Key: ✗ Not configured")
      lines.append("")
      lines.append("Set your Gemini API key in Settings or Keychain.")
      return lines
    }
    lines.append("API Key: ✓ Found")
    lines.append("Model: \(settings.geminiModel)")
    lines.append("")

    // Fetch model list
    do {
      let models = try await fetchGeminiModels(apiKey: apiKey)
      lines.append("Available models (\(models.count)):")
      let displayModels = models.prefix(20)
      for model in displayModels {
        let marker = model == settings.geminiModel ? " ← current" : ""
        lines.append("  • \(model)\(marker)")
      }
      if models.count > 20 {
        lines.append("  … and \(models.count - 20) more")
      }

      if !models.contains(settings.geminiModel) {
        lines.append("")
        lines.append("⚠ Current model \"\(settings.geminiModel)\" not found in model list.")
        if let suggested = chooseGeminiModel(from: models) {
          lines.append("  Suggested: \(suggested)")
        }
      }
    } catch {
      lines.append("✗ Failed to fetch models: \(error.localizedDescription)")
    }

    // Verify key works with a simple generation call
    lines.append("")
    lines.append("API Key Test:")
    do {
      let testResult = try await testGeminiApiKey(apiKey: apiKey, model: settings.geminiModel)
      if testResult {
        lines.append("  ✓ API key is valid and model responds")
      } else {
        lines.append("  ✗ API key or model issue — no response")
      }
    } catch {
      lines.append("  ✗ \(error.localizedDescription)")
    }

    return lines
  }

  private func diagnoseOpenRouter() async -> [String] {
    var lines: [String] = []
    let apiKey = currentOpenRouterApiKey()
    let hasKey = apiKey != nil && !apiKey!.isEmpty

    lines.append("API Key: \(hasKey ? "✓ Found" : "○ Not set (using keyless/free)")")
    lines.append("Current Model: \(settings.openRouterModel)")
    lines.append("")

    // Fetch free models
    lines.append("Scanning free models…")
    do {
      let allModels = try await fetchOpenRouterModels()
      let freeModels = allModels.filter { $0.hasSuffix(":free") }
      lines.removeLast() // remove "Scanning…"

      lines.append("Free models available (\(freeModels.count)):")
      let ranked = rankedOpenRouterModels(from: freeModels, preferFree: true, preferredFirst: nil, excluding: nil)
      let displayModels = ranked.prefix(15)
      for model in displayModels {
        let marker = model == settings.openRouterModel ? " ← current" : ""
        lines.append("  • \(model)\(marker)")
      }
      if ranked.count > 15 {
        lines.append("  … and \(ranked.count - 15) more")
      }

      // Auto-detect a working free model
      lines.append("")
      lines.append("Probing for a working free model…")
      let effectiveKey = apiKey ?? ""
      if let working = try await detectWorkingOpenRouterModel(
        apiKey: effectiveKey,
        preferFree: true,
        preferredFirst: settings.openRouterModel,
        excluding: nil
      ) {
        if working == settings.openRouterModel {
          lines.append("  ✓ Current model \"\(working)\" is working")
        } else {
          settings.openRouterModel = working
          persistSettings()
          lines.append("  ✓ Set model to \"\(working)\" (verified working)")
        }
      } else {
        lines.append("  ✗ No working free model found")
      }
    } catch {
      lines.append("✗ Failed to fetch models: \(error.localizedDescription)")
    }

    return lines
  }

  private func diagnoseOpenAI() async -> [String] {
    var lines: [String] = []
    guard let apiKey = currentOpenAIApiKey(), !apiKey.isEmpty else {
      lines.append("API Key: ✗ Not configured")
      lines.append("")
      lines.append("Set your OpenAI API key in Settings or Keychain.")
      return lines
    }
    lines.append("API Key: ✓ Found")
    lines.append("Model: \(settings.openAIModel)")
    lines.append("")

    // Fetch model list
    do {
      let models = try await fetchOpenAIModels(apiKey: apiKey)
      let chatModels = models.filter {
        $0.contains("gpt") || $0.contains("o1") || $0.contains("o3") || $0.contains("o4")
      }.sorted()
      lines.append("Chat models (\(chatModels.count)):")
      let displayModels = chatModels.prefix(20)
      for model in displayModels {
        let marker = model == settings.openAIModel ? " ← current" : ""
        lines.append("  • \(model)\(marker)")
      }
      if chatModels.count > 20 {
        lines.append("  … and \(chatModels.count - 20) more")
      }

      if !chatModels.contains(settings.openAIModel) && !models.contains(settings.openAIModel) {
        lines.append("")
        lines.append("⚠ Current model \"\(settings.openAIModel)\" not found.")
      }
    } catch {
      lines.append("✗ Failed to fetch models: \(error.localizedDescription)")
    }

    // Verify key
    lines.append("")
    lines.append("API Key Test:")
    do {
      let testResult = try await testOpenAIApiKey(apiKey: apiKey, model: settings.openAIModel)
      if testResult {
        lines.append("  ✓ API key is valid and model responds")
      } else {
        lines.append("  ✗ API key or model issue — no response")
      }
    } catch {
      lines.append("  ✗ \(error.localizedDescription)")
    }

    return lines
  }

  private func diagnoseAnthropic() async -> [String] {
    var lines: [String] = []
    guard let apiKey = currentAnthropicApiKey(), !apiKey.isEmpty else {
      lines.append("API Key: ✗ Not configured")
      lines.append("")
      lines.append("Set your Anthropic API key in Settings or Keychain.")
      return lines
    }
    lines.append("API Key: ✓ Found")
    lines.append("Model: \(settings.anthropicModel)")
    lines.append("")

    // Anthropic doesn't have a public model list endpoint, so just verify the key
    lines.append("API Key Test:")
    do {
      let testResult = try await testAnthropicApiKey(apiKey: apiKey, model: settings.anthropicModel)
      if testResult {
        lines.append("  ✓ API key is valid and model responds")
      } else {
        lines.append("  ✗ API key or model issue — no response")
      }
    } catch {
      lines.append("  ✗ \(error.localizedDescription)")
    }

    return lines
  }

  // MARK: - Diagnostic API Helpers

  private func testGeminiApiKey(apiKey: String, model: String) async throws -> Bool {
    guard let baseURL = URL(string: settings.geminiBaseURL) else { return false }
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return false }
    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    components.path = basePath + "/v1beta/models/\(model):generateContent"
    components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
    guard let url = components.url else { return false }

    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
      "contents": [["parts": [["text": "Reply OK"]]]],
      "generationConfig": ["maxOutputTokens": 8],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { return false }
    return (200..<300).contains(http.statusCode)
  }

  private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
    let url = URL(string: settings.openAIBaseURL + "/models")!
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "GET"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw NSError(domain: "TextPolish", code: 0, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
    }
    guard (200..<300).contains(http.statusCode) else {
      throw NSError(domain: "TextPolish", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
    }

    struct ModelsResponse: Decodable {
      struct Model: Decodable { let id: String }
      let data: [Model]?
    }
    let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
    return decoded.data?.map(\.id) ?? []
  }

  private func testOpenAIApiKey(apiKey: String, model: String) async throws -> Bool {
    let url = URL(string: settings.openAIBaseURL + "/chat/completions")!
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let body: [String: Any] = [
      "model": model,
      "messages": [["role": "user", "content": "Reply OK"]],
      "max_tokens": 8,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { return false }
    return (200..<300).contains(http.statusCode)
  }

  private func testAnthropicApiKey(apiKey: String, model: String) async throws -> Bool {
    let url = URL(string: settings.anthropicBaseURL + "/v1/messages")!
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    let body: [String: Any] = [
      "model": model,
      "max_tokens": 8,
      "messages": [["role": "user", "content": "Reply OK"]],
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { return false }
    return (200..<300).contains(http.statusCode)
  }

  private func setCorrectionLanguage(_ language: Settings.CorrectionLanguage) {
    guard settings.correctionLanguage != language else { return }
    settings.correctionLanguage = language
    persistSettings()
    syncLanguageMenuState()
  }

  private func isRunningFromApplicationsFolder() -> Bool {
    let path = Bundle.main.bundleURL.standardizedFileURL.path
    return path.hasPrefix("/Applications/")
  }

  private func maybeShowWelcome() {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: didShowWelcomeKey) == false else { return }
    defaults.set(true, forKey: didShowWelcomeKey)

    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "\(appDisplayName) is running"
    alert.informativeText = [
      "Look for the menu bar icon (top right).",
      "If you quit, you can relaunch from Finder → Applications → \(expectedAppName).",
      "",
      "1) Grant Accessibility permission (required for ⌘C/⌘V/⌘A).",
      "2) Set an API key: Provider → Set Gemini API Key… or Set OpenRouter API Key…",
      "",
      "Shortcuts:",
      "• Correct Selection: \(settings.hotKeyCorrectSelection.displayString)",
      "• Correct All: \(settings.hotKeyCorrectAll.displayString)",
    ].joined(separator: "\n")

    alert.addButton(withTitle: "Open Accessibility Settings")
    alert.addButton(withTitle: "Set API Key…")
    alert.addButton(withTitle: "Later")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
      openAccessibilitySettings()
    case .alertSecondButtonReturn:
      if settings.provider == .openRouter {
        setOpenRouterApiKey()
      } else {
        setGeminiApiKey()
      }
    default:
      break
    }
  }

  private func showStartAtLoginRequiresApplications() {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "Move \(appDisplayName) to /Applications"
    alert.informativeText = "Start at Login is most reliable when the app is in /Applications. Install the app there (for example via the .pkg), then enable Start at Login again."
    alert.addButton(withTitle: "OK")
    _ = alert.runModal()
  }

  private func detectGeminiModelAsync() async {
    guard let apiKey = currentGeminiApiKey() else {
      showSimpleAlert(title: "Missing Gemini API Key", message: "Set it via Provider → Set Gemini API Key…")
      return
    }

    do {
      let models = try await fetchGeminiModels(apiKey: apiKey)
      guard let chosen = chooseGeminiModel(from: models) else {
        showSimpleAlert(title: "No Models Found", message: "Gemini returned no usable models for this API key.")
        return
      }

      settings.geminiModel = chosen
      persistSettings()
      syncProviderMenuStates()
      refreshCorrector()
      showSimpleAlert(title: "Gemini Model Updated", message: "Using: \(chosen)")
    } catch {
      let message =
        (error as? LocalizedError)?.errorDescription ??
        (error as NSError).localizedDescription
      showSimpleAlert(title: "Detect Model Failed", message: message)
    }
  }

  private func detectOpenRouterModelAsync() async {
    guard let apiKey = currentOpenRouterApiKey() else {
      showSimpleAlert(title: "Missing OpenRouter API Key", message: "Set it via Provider → Set OpenRouter API Key…")
      return
    }

    do {
      let current = settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let chosen = try await detectWorkingOpenRouterModel(
        apiKey: apiKey,
        preferFree: false,
        preferredFirst: current.isEmpty ? nil : current,
        excluding: nil
      ) else {
        showSimpleAlert(title: "No Working Model Found", message: "OpenRouter didn’t return a working model for this API key. Try setting a model manually.")
        return
      }

      if chosen == current, !current.isEmpty {
        showSimpleAlert(title: "OpenRouter Model OK", message: "Current model works: \(chosen)")
        return
      }

      settings.openRouterModel = chosen
      persistSettings()
      syncProviderMenuStates()
      refreshCorrector()
      showSimpleAlert(title: "OpenRouter Model Updated", message: "Using: \(chosen)")
    } catch {
      let message =
        (error as? LocalizedError)?.errorDescription ??
        (error as NSError).localizedDescription
      showSimpleAlert(title: "Detect Model Failed", message: message)
    }
  }

  private func currentGeminiApiKey() -> String? {
    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountGemini))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromKeychain.isEmpty { return keyFromKeychain }

    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountGemini))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromLegacyKeychain.isEmpty { return keyFromLegacyKeychain }

    let keyFromSettings = settings.geminiApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromSettings.isEmpty { return keyFromSettings }

    let env =
      ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ??
      ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] ??
      ""
    let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
    return keyFromEnv.isEmpty ? nil : keyFromEnv
  }

  private func currentOpenRouterApiKey() -> String? {
    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountOpenRouter))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromKeychain.isEmpty { return keyFromKeychain }

    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountOpenRouter))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromLegacyKeychain.isEmpty { return keyFromLegacyKeychain }

    let keyFromSettings = settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromSettings.isEmpty { return keyFromSettings }

    let env = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
    let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
    return keyFromEnv.isEmpty ? nil : keyFromEnv
  }

  private func currentOpenAIApiKey() -> String? {
    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountOpenAI))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromKeychain.isEmpty { return keyFromKeychain }

    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountOpenAI))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromLegacyKeychain.isEmpty { return keyFromLegacyKeychain }

    let keyFromSettings = settings.openAIApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromSettings.isEmpty { return keyFromSettings }

    let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
    return keyFromEnv.isEmpty ? nil : keyFromEnv
  }

  private func currentAnthropicApiKey() -> String? {
    let keyFromKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccountAnthropic))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromKeychain.isEmpty { return keyFromKeychain }

    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccountAnthropic))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromLegacyKeychain.isEmpty { return keyFromLegacyKeychain }

    let keyFromSettings = settings.anthropicApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromSettings.isEmpty { return keyFromSettings }

    let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    let keyFromEnv = env.trimmingCharacters(in: .whitespacesAndNewlines)
    return keyFromEnv.isEmpty ? nil : keyFromEnv
  }

  private struct GeminiModelsResponse: Decodable {
    struct Model: Decodable {
      let name: String
      let supportedGenerationMethods: [String]?
    }
    let models: [Model]?
  }

  private struct OpenRouterModelsResponse: Decodable {
    struct Model: Decodable {
      let id: String
    }
    let data: [Model]?
  }

  private struct OpenRouterChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
      struct Message: Decodable {
        let content: String?
      }
      let message: Message?
    }
    let choices: [Choice]?
  }

  private struct OpenAIErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
      let message: String?
      let code: String?
      let type: String?
    }
    let error: ErrorBody?
  }

  private func parseOpenRouterErrorMessage(data: Data) -> String? {
    if let decoded = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
      let message = ErrorLogSanitizer.sanitize(decoded.error?.message)
      if let message, !message.isEmpty { return message }
    }

    if let string = String(data: data, encoding: .utf8) {
      return ErrorLogSanitizer.sanitize(string)
    }

    return nil
  }

  private func makeOpenRouterChatCompletionsURL() throws -> URL {
    guard let baseURL = URL(string: settings.openRouterBaseURL) else {
      throw NSError(domain: "TextPolish", code: 20, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
    }
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw NSError(domain: "TextPolish", code: 20, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
    }
    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    components.path = basePath + "/chat/completions"
    guard let url = components.url else {
      throw NSError(domain: "TextPolish", code: 21, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter URL"])
    }
    return url
  }

  private func probeOpenRouterModel(apiKey: String, model: String) async throws -> Bool {
    let url = try makeOpenRouterChatCompletionsURL()
    var request = URLRequest(url: url, timeoutInterval: settings.requestTimeoutSeconds)
    request.httpMethod = "POST"
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("TextPolish", forHTTPHeaderField: "X-Title")
    request.setValue("https://github.com/kxxil01", forHTTPHeaderField: "HTTP-Referer")

    let body: [String: Any] = [
      "model": model,
      "messages": [
        ["role": "user", "content": "Reply with ONLY the word OK."],
      ],
      "temperature": 0.0,
      "max_tokens": 8,
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { return false }

    if (200..<300).contains(http.statusCode) {
      let decoded = try JSONDecoder().decode(OpenRouterChatCompletionsResponse.self, from: data)
      let content = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return !content.isEmpty
    }

    let message = ErrorLogSanitizer.sanitize(parseOpenRouterErrorMessage(data: data))
    NSLog("[TextPolish] OpenRouter probe HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
    if http.statusCode == 401 {
      throw NSError(domain: "TextPolish", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenRouter unauthorized (401) — check API key"])
    }
    return false
  }

  private func detectWorkingOpenRouterModel(
    apiKey: String,
    preferFree: Bool,
    preferredFirst: String?,
    excluding: String?
  ) async throws -> String? {
    let models = try await fetchOpenRouterModels()
    let candidates = rankedOpenRouterModels(from: models, preferFree: preferFree, preferredFirst: preferredFirst, excluding: excluding)
    let limit = min(20, candidates.count)

    for model in candidates.prefix(limit) {
      let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if try await probeOpenRouterModel(apiKey: apiKey, model: trimmed) {
        return trimmed
      }
    }

    return nil
  }

  private func fetchOpenRouterModels() async throws -> [String] {
    guard let baseURL = URL(string: settings.openRouterBaseURL) else {
      throw NSError(domain: "TextPolish", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
    }
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw NSError(domain: "TextPolish", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenRouter base URL"])
    }

    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    components.path = basePath + "/models"

    guard let url = components.url else {
      throw NSError(domain: "TextPolish", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid models URL"])
    }

    var request = URLRequest(url: url, timeoutInterval: settings.requestTimeoutSeconds)
    request.httpMethod = "GET"
    request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw NSError(domain: "TextPolish", code: 12, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
    }

    if (200..<300).contains(http.statusCode) {
      let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
      let models = decoded.data ?? []
      return models.map(\.id)
    }

    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    throw NSError(
      domain: "TextPolish",
      code: http.statusCode,
      userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "HTTP \(http.statusCode)" : "HTTP \(http.statusCode): \(text.prefix(240))"]
    )
  }

  private func fetchGeminiModels(apiKey: String) async throws -> [String] {
    guard let baseURL = URL(string: settings.geminiBaseURL) else {
      throw NSError(domain: "TextPolish", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini base URL"])
    }

    let versionsToTry = ["v1beta", "v1"]
    var lastError: Error?

    for (index, version) in versionsToTry.enumerated() {
      guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
        throw NSError(domain: "TextPolish", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini base URL"])
      }
      var basePath = components.path
      if basePath.hasSuffix("/") { basePath.removeLast() }
      components.path = basePath + "/\(version)/models"

      var items = components.queryItems ?? []
      items.removeAll { $0.name == "key" }
      items.append(URLQueryItem(name: "key", value: apiKey))
      components.queryItems = items
      guard let url = components.url else {
        throw NSError(domain: "TextPolish", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid models URL"])
      }

      var request = URLRequest(url: url, timeoutInterval: settings.requestTimeoutSeconds)
      request.httpMethod = "GET"
      request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = NSError(domain: "TextPolish", code: 3, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        continue
      }

      if (200..<300).contains(http.statusCode) {
        let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let models = decoded.models ?? []
        return models.compactMap { model in
          let supports = model.supportedGenerationMethods ?? []
          guard supports.isEmpty || supports.contains("generateContent") else { return nil }
          return model.name.hasPrefix("models/") ? String(model.name.dropFirst("models/".count)) : model.name
        }
      }

      let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let error = NSError(
        domain: "TextPolish",
        code: http.statusCode,
        userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "HTTP \(http.statusCode)" : "HTTP \(http.statusCode): \(text.prefix(240))"]
      )

      if http.statusCode == 404, index < versionsToTry.count - 1 {
        lastError = error
        continue
      }

      throw error
    }

    throw lastError ?? NSError(domain: "TextPolish", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
  }

  private func chooseGeminiModel(from models: [String]) -> String? {
    guard !models.isEmpty else { return nil }

    func score(_ name: String) -> Int {
      let lower = name.lowercased()
      var value = 0
      if lower.contains("flash") { value += 100 }
      if lower.contains("2.0") { value += 20 }
      if lower.contains("1.5") { value += 10 }
      if lower.contains("lite") { value += 10 }
      if lower.contains("latest") { value += 5 }
      if lower.contains("preview") { value -= 50 }
      if lower.contains("exp") || lower.contains("experimental") { value -= 50 }
      if lower.contains("pro") { value -= 5 }
      return value
    }

    return models
      .map { ($0, score($0)) }
      .max(by: { $0.1 < $1.1 })?
      .0
  }

  private func openRouterScore(_ id: String) -> Int {
    let lower = id.lowercased()
    var value = 0
    if lower == "openai/gpt-4o-mini" { value += 960 }
    if lower == "google/gemini-2.0-flash-lite-001" { value += 940 }
    if lower == "google/gemini-2.0-flash-exp:free" { value += 880 }
    if lower == "meta-llama/llama-3.2-3b-instruct:free" { value += 860 }
    if lower == "qwen/qwen3-4b:free" { value += 820 }
    if lower.contains("gemini") { value += 260 }
    if lower.contains("flash") { value += 220 }
    if lower.contains("2.0") { value += 50 }
    if lower.contains("lite") { value += 30 }
    if lower.contains("gpt-4o-mini") { value += 240 }
    if lower.contains("llama-3.2") { value += 90 }
    if lower.contains("3b") { value += 30 }
    if lower.contains("instruct") { value += 20 }
    if lower.contains(":free") { value += 40 }
    if lower.contains("preview") { value -= 40 }
    if lower.contains("think") { value -= 90 }
    if lower.contains("creative") { value -= 40 }
    return value
  }

  private func rankedOpenRouterModels(
    from models: [String],
    preferFree: Bool,
    preferredFirst: String?,
    excluding: String?
  ) -> [String] {
    guard !models.isEmpty else { return [] }

    let filtered = preferFree ? models.filter { $0.hasSuffix(":free") } : models
    var pool = filtered.isEmpty ? models : filtered
    if let excluding, !excluding.isEmpty {
      pool.removeAll { $0 == excluding }
    }

    pool.sort(by: { openRouterScore($0) > openRouterScore($1) })

    guard let preferredFirst, !preferredFirst.isEmpty else { return pool }
    if preferredFirst == excluding { return pool }

    var result: [String] = [preferredFirst]
    result.append(contentsOf: pool.filter { $0 != preferredFirst })
    return result
  }

  private func showSimpleAlert(title: String, message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private enum ApiKeyPromptResult {
    case save(String)
    case clear
    case canceled
  }

  private func apiKeyPromptResultKind(_ result: ApiKeyPromptResult) -> String {
    switch result {
    case .save:
      return "save"
    case .clear:
      return "clear"
    case .canceled:
      return "canceled"
    }
  }

  private func promptForApiKey(title: String, message: String) -> ApiKeyPromptResult {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational

    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
    field.placeholderString = "Paste API key (⌘V or ⌃V)"
    field.isEditable = true
    field.isSelectable = true
    field.allowsEditingTextAttributes = false
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingMiddle
    field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    field.cell?.wraps = false
    field.cell?.isScrollable = true
    alert.accessoryView = field

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Clear")

    let window = alert.window
    window.level = .floating
    DispatchQueue.main.async { [weak field] in
      guard let field, let window = field.window, window.isVisible else { return }
      window.makeFirstResponder(field)
      field.selectText(nil)
    }

    let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let wantsPaste =
        (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)) &&
        event.charactersIgnoringModifiers?.lowercased() == "v"
      if wantsPaste
      {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        return nil
      }
      return event
    }
    defer {
      if let monitor { NSEvent.removeMonitor(monitor) }
    }

    let response = alert.runModal()
    window.orderOut(nil)
    switch response {
    case .alertFirstButtonReturn: // Save
      let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else {
        NSSound.beep()
        return .canceled
      }
      return .save(value)
    case .alertThirdButtonReturn: // Clear
      return .clear
    default:
      return .canceled
    }
  }

  private func promptForText(title: String, message: String, placeholder: String, initialValue: String) -> String? {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational

    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
    field.placeholderString = placeholder
    field.usesSingleLineMode = true
    field.lineBreakMode = .byTruncatingMiddle
    field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    field.cell?.wraps = false
    field.cell?.isScrollable = true
    field.stringValue = initialValue
    alert.accessoryView = field

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")

    let window = alert.window
    window.level = .floating
    DispatchQueue.main.async { [weak field] in
      guard let field, let window = field.window, window.isVisible else { return }
      window.makeFirstResponder(field)
      field.selectText(nil)
    }

    let response = alert.runModal()
    window.orderOut(nil)
    guard response == .alertFirstButtonReturn else { return nil }
    return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @objc private func openSettingsFile() {
    NSWorkspace.shared.open(Settings.settingsFileURL())
  }

  @objc private func openAccessibilitySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func showAboutAndPrivacy() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
      let header = "\(appDisplayName) \(version)"

      let providerName: String
      let providerModel: String
      let providerURL: String
      switch self.settings.provider {
      case .gemini:
        providerName = "Gemini (Google)"
        providerModel = self.settings.geminiModel
        providerURL = self.settings.geminiBaseURL
      case .openRouter:
        providerName = "OpenRouter"
        providerModel = self.settings.openRouterModel
        providerURL = self.settings.openRouterBaseURL
      case .openAI:
        providerName = "OpenAI"
        providerModel = self.settings.openAIModel
        providerURL = self.settings.openAIBaseURL
      case .anthropic:
        providerName = "Anthropic"
        providerModel = self.settings.anthropicModel
        providerURL = self.settings.anthropicBaseURL
      }

      let settingsPath = Settings.settingsFileURL().path

      let message = [
        "Small, fast menu bar text polish for grammar and tone. Minimal edits, keeps formatting.",
        "",
        "Shortcuts:",
        "• Correct Selection: \(settings.hotKeyCorrectSelection.displayString)",
        "• Correct All: \(settings.hotKeyCorrectAll.displayString)",
        "• Tone Analysis: \(settings.hotKeyAnalyzeTone.displayString)",
        "",
        "Provider:",
        "• Provider: \(providerName)",
        "• Model: \(providerModel)",
        "• URL: \(providerURL)",
        "",
        "Usage:",
        "• Badge shows total successful corrections + analyses today (resets daily)",
        "• Optional automatic fallback to alternate provider on errors",
        "",
        "Updates:",
        "• Delivered via GitHub Releases",
        "• Check from the menu: Check for Updates > Check",
        "",
        "Security:",
        "• API keys stored in macOS Keychain",
        "• No analytics or telemetry",
        "",
        "Privacy:",
        "• Text stays on-device until you trigger an action",
        "• Copies selected text temporarily and restores your clipboard",
        "• Sends only selected text to the provider over HTTPS",
        "• Pastes corrected text back (tone analysis shows a window instead)",
        "• TextPolish does not store your text",
        "• Provider may log requests per their policy",
        "• Settings stored at \(settingsPath)",
        "• Keychain service: \(self.keychainService)",
        "",
        "Requires Accessibility permission to send ⌘C, ⌘V, and ⌘A.",
        "",
        "Creator: Kurniadi Ilham",
        "GitHub: https://github.com/kxxil01",
        "LinkedIn: https://linkedin.com/in/kurniadi-ilham",
      ].joined(separator: "\n")

      self.showSimpleAlert(title: header, message: message)
    }
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  @objc private func setCorrectSelectionHotKey() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let title = "Set Correct Selection Hotkey"
      let message = "Current: \(self.settings.hotKeyCorrectSelection.displayString)\n\nPress a key combination to change it."
      if let newHotKey = self.promptForHotKey(title: title, message: message, defaultHotKey: .correctSelectionDefault) {
        if newHotKey == self.settings.hotKeyCorrectSelection {
          return
        }
        if newHotKey == self.settings.hotKeyCorrectAll {
          let oldSelection = self.settings.hotKeyCorrectSelection
          let oldAll = self.settings.hotKeyCorrectAll
          self.settings.hotKeyCorrectSelection = oldAll
          self.settings.hotKeyCorrectAll = oldSelection
          self.persistSettings()
          do {
            try self.hotKeyManager.registerHotKeys(
              correctSelection: self.settings.hotKeyCorrectSelection,
              correctAll: self.settings.hotKeyCorrectAll,
              analyzeTone: self.settings.hotKeyAnalyzeTone
            )
            self.syncHotKeyMenuItems()
          } catch {
            self.settings.hotKeyCorrectSelection = oldSelection
            self.settings.hotKeyCorrectAll = oldAll
            self.persistSettings()
            self.showSimpleAlert(title: "Failed to Register Hotkey", message: "\(error)")
          }
          return
        }
        if HotKeyManager.isHotKeyInUse(
          hotKey: newHotKey,
          ignoring: [self.settings.hotKeyCorrectSelection, self.settings.hotKeyCorrectAll, self.settings.hotKeyAnalyzeTone]
        ) {
          self.showSimpleAlert(title: "Hotkey Already in Use", message: "This combination is already used by another application.")
          return
        }
        let oldHotKey = self.settings.hotKeyCorrectSelection
        self.settings.hotKeyCorrectSelection = newHotKey
        self.persistSettings()
        do {
          try self.hotKeyManager.registerHotKeys(
            correctSelection: self.settings.hotKeyCorrectSelection,
            correctAll: self.settings.hotKeyCorrectAll,
            analyzeTone: self.settings.hotKeyAnalyzeTone
          )
          self.syncHotKeyMenuItems()
        } catch {
          self.settings.hotKeyCorrectSelection = oldHotKey
          self.persistSettings()
          self.showSimpleAlert(title: "Failed to Register Hotkey", message: "\(error)")
        }
      }
    }
  }

  @objc private func setCorrectAllHotKey() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let title = "Set Correct All Hotkey"
      let message = "Current: \(self.settings.hotKeyCorrectAll.displayString)\n\nPress a key combination to change it."
      if let newHotKey = self.promptForHotKey(title: title, message: message, defaultHotKey: .correctAllDefault) {
        if newHotKey == self.settings.hotKeyCorrectAll {
          return
        }
        if newHotKey == self.settings.hotKeyCorrectSelection {
          let oldSelection = self.settings.hotKeyCorrectSelection
          let oldAll = self.settings.hotKeyCorrectAll
          self.settings.hotKeyCorrectSelection = oldAll
          self.settings.hotKeyCorrectAll = oldSelection
          self.persistSettings()
          do {
            try self.hotKeyManager.registerHotKeys(
              correctSelection: self.settings.hotKeyCorrectSelection,
              correctAll: self.settings.hotKeyCorrectAll,
              analyzeTone: self.settings.hotKeyAnalyzeTone
            )
            self.syncHotKeyMenuItems()
          } catch {
            self.settings.hotKeyCorrectSelection = oldSelection
            self.settings.hotKeyCorrectAll = oldAll
            self.persistSettings()
            self.showSimpleAlert(title: "Failed to Register Hotkey", message: "\(error)")
          }
          return
        }
        if HotKeyManager.isHotKeyInUse(
          hotKey: newHotKey,
          ignoring: [self.settings.hotKeyCorrectSelection, self.settings.hotKeyCorrectAll, self.settings.hotKeyAnalyzeTone]
        ) {
          self.showSimpleAlert(title: "Hotkey Already in Use", message: "This combination is already used by another application.")
          return
        }
        let oldHotKey = self.settings.hotKeyCorrectAll
        self.settings.hotKeyCorrectAll = newHotKey
        self.persistSettings()
        do {
          try self.hotKeyManager.registerHotKeys(
            correctSelection: self.settings.hotKeyCorrectSelection,
            correctAll: self.settings.hotKeyCorrectAll,
            analyzeTone: self.settings.hotKeyAnalyzeTone
          )
          self.syncHotKeyMenuItems()
        } catch {
          self.settings.hotKeyCorrectAll = oldHotKey
          self.persistSettings()
          self.showSimpleAlert(title: "Failed to Register Hotkey", message: "\(error)")
        }
      }
    }
  }

  @objc private func setAnalyzeToneHotKey() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let title = "Set Analyze Tone Hotkey"
      let message = "Current: \(self.settings.hotKeyAnalyzeTone.displayString)\n\nPress a key combination to change it."
      if let newHotKey = self.promptForHotKey(title: title, message: message, defaultHotKey: .analyzeToneDefault) {
        if newHotKey == self.settings.hotKeyAnalyzeTone {
          return
        }
        if HotKeyManager.isHotKeyInUse(
          hotKey: newHotKey,
          ignoring: [self.settings.hotKeyCorrectSelection, self.settings.hotKeyCorrectAll, self.settings.hotKeyAnalyzeTone]
        ) {
          self.showSimpleAlert(title: "Hotkey Already in Use", message: "This combination is already used by another application.")
          return
        }
        let oldHotKey = self.settings.hotKeyAnalyzeTone
        self.settings.hotKeyAnalyzeTone = newHotKey
        self.persistSettings()
        do {
          try self.hotKeyManager.registerHotKeys(
            correctSelection: self.settings.hotKeyCorrectSelection,
            correctAll: self.settings.hotKeyCorrectAll,
            analyzeTone: self.settings.hotKeyAnalyzeTone
          )
          self.syncHotKeyMenuItems()
        } catch {
          self.settings.hotKeyAnalyzeTone = oldHotKey
          self.persistSettings()
          self.showSimpleAlert(title: "Failed to Register Hotkey", message: "\(error)")
        }
      }
    }
  }

  @objc private func resetHotKeys() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      self.settings.hotKeyCorrectSelection = .correctSelectionDefault
      self.settings.hotKeyCorrectAll = .correctAllDefault
      self.settings.hotKeyAnalyzeTone = .analyzeToneDefault
      self.persistSettings()
      do {
        try self.hotKeyManager.registerHotKeys(
          correctSelection: self.settings.hotKeyCorrectSelection,
          correctAll: self.settings.hotKeyCorrectAll,
          analyzeTone: self.settings.hotKeyAnalyzeTone
        )
        self.syncHotKeyMenuItems()
        self.showSimpleAlert(title: "Hotkeys Reset", message: "Hotkeys have been reset to defaults.")
      } catch {
        self.showSimpleAlert(title: "Failed to Reset Hotkeys", message: "\(error)")
      }
    }
  }

  private func syncHotKeyMenuItems() {
    let selectionHotKey = settings.hotKeyCorrectSelection
    let allHotKey = settings.hotKeyCorrectAll
    let analyzeToneHotKey = settings.hotKeyAnalyzeTone

    selectionItem?.title = "Correct Selection"
    selectionItem?.keyEquivalent = Settings.HotKey.keyEquivalentString(keyCode: selectionHotKey.keyCode)
    selectionItem?.keyEquivalentModifierMask = Settings.HotKey.modifierMask(modifiers: selectionHotKey.modifiers)

    allItem?.title = "Correct All"
    allItem?.keyEquivalent = Settings.HotKey.keyEquivalentString(keyCode: allHotKey.keyCode)
    allItem?.keyEquivalentModifierMask = Settings.HotKey.modifierMask(modifiers: allHotKey.modifiers)

    analyzeToneItem?.title = "Analyze Tone"
    analyzeToneItem?.keyEquivalent = Settings.HotKey.keyEquivalentString(keyCode: analyzeToneHotKey.keyCode)
    analyzeToneItem?.keyEquivalentModifierMask = Settings.HotKey.modifierMask(modifiers: analyzeToneHotKey.modifiers)
  }

  private func syncCancelMenuState() {
    cancelCorrectionItem?.isEnabled = correctionController?.isBusy == true
  }

  private func promptForHotKey(title: String, message: String, defaultHotKey: Settings.HotKey) -> Settings.HotKey? {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational

    let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    textField.isEditable = false
    textField.isSelectable = false
    textField.alignment = .center
    textField.font = NSFont.systemFont(ofSize: 14)
    textField.placeholderString = "Press a key combination"
    alert.accessoryView = textField

    alert.addButton(withTitle: "Cancel")
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Record")

    let window = alert.window
    window.level = .floating

    DispatchQueue.main.async { [weak textField] in
      guard let textField, let window = textField.window, window.isVisible else { return }
      textField.stringValue = "Press keys..."
    }

    var capturedHotKey: Settings.HotKey? = nil
    let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak textField] event in
      let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

      let keyCode = event.keyCode

      if event.type == .flagsChanged {
        return event
      }

      if keyCode == 53 {
        NSApp.stopModal(withCode: .alertFirstButtonReturn)
        return nil
      }

      if keyCode == 48 {
        NSApp.stopModal(withCode: .alertSecondButtonReturn)
        return nil
      }

      if modifiers.isEmpty {
        textField?.stringValue = "Add a modifier (Command/Option/Control/Shift)"
        NSSound.beep()
        return nil
      }

      var carbonModifiers: UInt32 = 0
      if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
      if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
      if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
      if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

      capturedHotKey = Settings.HotKey(keyCode: UInt32(keyCode), modifiers: carbonModifiers)
      NSApp.stopModal(withCode: .alertThirdButtonReturn)
      return nil
    }

    let response = alert.runModal()
    window.orderOut(nil)
    if let monitor { NSEvent.removeMonitor(monitor) }

    switch response {
    case .alertThirdButtonReturn:
      return capturedHotKey
    case .alertSecondButtonReturn:
      return defaultHotKey
    default:
      return nil
    }
  }
}

extension AppDelegate: SPUUpdaterDelegate {
  nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.updateFoundInCycle = true
      self.updateStatus = .available
      self.recordLastUpdateCheck()
      self.syncUpdateMenuItems()
      if self.manualUpdateCheckInProgress {
        self.feedback?.showInfo("Update available.")
      }
    }
  }

  nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    let nsError = error as NSError
    Task { @MainActor [weak self] in
      guard let self else { return }
      let feedback = UpdateCheckFeedback.fromSparkleError(nsError)
      self.updateFoundInCycle = false
      self.updateStatus = .message(feedback.message)
      self.recordLastUpdateCheck()
      self.syncUpdateMenuItems()
      if self.manualUpdateCheckInProgress {
        self.finishManualUpdateCheck(with: feedback)
      }
    }
  }

  nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    let nsError = error as NSError?
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard updateCheck == .updates else { return }

      let foundUpdate = self.updateFoundInCycle
      self.updateFoundInCycle = false
      if foundUpdate {
        self.updateStatus = .available
        self.recordLastUpdateCheck()
        self.syncUpdateMenuItems()
        if self.manualUpdateCheckInProgress {
          self.finishManualUpdateCheck(with: nil)
        }
        return
      }

      if let nsError {
        let feedback = UpdateCheckFeedback.fromSparkleError(nsError)
        self.updateStatus = .message(feedback.message)
        self.recordLastUpdateCheck()
        self.syncUpdateMenuItems()
        if self.manualUpdateCheckInProgress {
          self.finishManualUpdateCheck(with: feedback)
        }
        return
      }

      self.updateStatus = .upToDate
      self.recordLastUpdateCheck()
      self.syncUpdateMenuItems()
      if self.manualUpdateCheckInProgress {
        self.finishManualUpdateCheck(with: UpdateCheckFeedback(kind: .info, message: "You're up to date."))
      }
    }
  }
}
