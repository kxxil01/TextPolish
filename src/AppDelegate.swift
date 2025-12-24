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
  private var feedback: StatusItemFeedback?
  private var statusMenu: NSMenu?
  private var lastTargetApplication: NSRunningApplication?
  private var workspaceActivationObserver: Any?
  private var isMenuOpen = false
  private var pendingAfterMenuAction: (@MainActor () async -> Void)?
  private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  private var backendGeminiItem: NSMenuItem?
  private var backendOpenRouterItem: NSMenuItem?
  private var setGeminiKeyItem: NSMenuItem?
  private var setGeminiModelItem: NSMenuItem?
  private var detectGeminiModelItem: NSMenuItem?
  private var setOpenRouterKeyItem: NSMenuItem?
  private var setOpenRouterModelItem: NSMenuItem?
  private var detectOpenRouterModelItem: NSMenuItem?
  private var launchAtLoginItem: NSMenuItem?
  private var selectionItem: NSMenuItem?
  private var allItem: NSMenuItem?
  private var checkForUpdatesItem: NSMenuItem?

  private let keychainAccountGemini = "geminiApiKey"
  private let keychainAccountOpenRouter = "openRouterApiKey"
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let expectedBundleIdentifier = "com.kxxil01.TextPolish"
  private var keychainService: String {
    Bundle.main.bundleIdentifier ?? expectedBundleIdentifier
  }

  private let didShowWelcomeKey = "didShowWelcome_0_1"
  private let expectedAppName = "TextPolish"

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
    statusItem.button?.image = baseImage
    statusItem.button?.toolTip = appDisplayName
    statusItem.button?.target = self
    statusItem.button?.action = #selector(statusItemClicked(_:))
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

    let feedback = StatusItemFeedback(statusItem: statusItem, baseImage: baseImage)
    self.feedback = feedback
    correctionController = CorrectionController(
      corrector: CorrectorFactory.make(settings: settings),
      feedback: feedback,
      timings: .init(settings: settings),
      recoverer: { [weak self] error in
        guard let self else { return nil }
        return await self.recoverFromError(error)
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

    setupMenu()
    setupHotKeys()
    _ = updaterController
    if !isUpdaterAvailable {
      updaterController.updater.automaticallyChecksForUpdates = false
    }
    maybeShowWelcome()
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    captureFrontmostApplication()
    syncLaunchAtLoginMenuState()
    guard let statusMenu, let button = statusItem.button else { return }
    button.highlight(true)
    statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    button.highlight(false)
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    updaterController.checkForUpdates(sender)
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

    self.selectionItem = selectionItem
    self.allItem = allItem

    menu.addItem(selectionItem)
    menu.addItem(allItem)
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

    let resetHotKeysItem = NSMenuItem(
      title: "Reset to Defaults",
      action: #selector(resetHotKeys),
      keyEquivalent: ""
    )
    resetHotKeysItem.target = self

    hotKeysMenu.addItem(setSelectionHotKeyItem)
    hotKeysMenu.addItem(setAllHotKeyItem)
    hotKeysMenu.addItem(.separator())
    hotKeysMenu.addItem(resetHotKeysItem)

    hotKeysItem.submenu = hotKeysMenu
    menu.addItem(hotKeysItem)
    menu.addItem(.separator())

    let backendItem = NSMenuItem(title: "Backend", action: nil, keyEquivalent: "")
    let backendMenu = NSMenu()

    let geminiItem = NSMenuItem(
      title: "Gemini",
      action: #selector(selectGeminiBackend),
      keyEquivalent: ""
    )
    geminiItem.target = self

    let openRouterItem = NSMenuItem(
      title: "OpenRouter",
      action: #selector(selectOpenRouterBackend),
      keyEquivalent: ""
    )
    openRouterItem.target = self

    backendGeminiItem = geminiItem
    backendOpenRouterItem = openRouterItem
    syncBackendMenuStates()

    backendMenu.addItem(geminiItem)
    backendMenu.addItem(openRouterItem)
    backendMenu.addItem(.separator())

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

    self.setGeminiKeyItem = setGeminiKeyItem
    self.setGeminiModelItem = setGeminiModelItem
    self.detectGeminiModelItem = detectGeminiModelItem
    self.setOpenRouterKeyItem = setOpenRouterKeyItem
    self.setOpenRouterModelItem = setOpenRouterModelItem
    self.detectOpenRouterModelItem = detectOpenRouterModelItem

    backendMenu.addItem(setGeminiKeyItem)
    backendMenu.addItem(setGeminiModelItem)
    backendMenu.addItem(detectGeminiModelItem)
    backendMenu.addItem(setOpenRouterKeyItem)
    backendMenu.addItem(setOpenRouterModelItem)
    backendMenu.addItem(detectOpenRouterModelItem)

    backendItem.submenu = backendMenu
    menu.addItem(backendItem)

    let launchAtLoginItem = NSMenuItem(
      title: "Start at Login",
      action: #selector(toggleLaunchAtLogin),
      keyEquivalent: ""
    )
    launchAtLoginItem.target = self
    self.launchAtLoginItem = launchAtLoginItem
    menu.addItem(launchAtLoginItem)

    let openSettingsItem = NSMenuItem(
      title: "Advanced: Open Settings File…",
      action: #selector(openSettingsFile),
      keyEquivalent: ""
    )
    openSettingsItem.target = self
    menu.addItem(openSettingsItem)

    let accessibilityItem = NSMenuItem(
      title: "Open Accessibility Settings…",
      action: #selector(openAccessibilitySettings),
      keyEquivalent: ""
    )
    accessibilityItem.target = self
    menu.addItem(accessibilityItem)

    let revealItem = NSMenuItem(
      title: "Reveal App in Finder…",
      action: #selector(revealAppInFinder),
      keyEquivalent: ""
    )
    revealItem.target = self
    menu.addItem(revealItem)

    let privacyItem = NSMenuItem(
      title: "Privacy…",
      action: #selector(showPrivacy),
      keyEquivalent: ""
    )
    privacyItem.target = self
    menu.addItem(privacyItem)

    let aboutItem = NSMenuItem(
      title: "About \(expectedAppName)…",
      action: #selector(showAbout),
      keyEquivalent: ""
    )
    aboutItem.target = self
    menu.addItem(aboutItem)

    let checkForUpdatesItem = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(checkForUpdates),
      keyEquivalent: ""
    )
    checkForUpdatesItem.target = self
    checkForUpdatesItem.isEnabled = isUpdaterAvailable
    if !isUpdaterAvailable {
      checkForUpdatesItem.toolTip = "Updates are not configured for this build."
    }
    self.checkForUpdatesItem = checkForUpdatesItem
    menu.addItem(checkForUpdatesItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    quitItem.keyEquivalentModifierMask = [.command]
    menu.addItem(quitItem)

    statusMenu = menu
    syncLaunchAtLoginMenuState()
    syncBackendMenuStates()
    syncHotKeyMenuItems()
  }

  func menuWillOpen(_ menu: NSMenu) {
    isMenuOpen = true
  }

  func menuDidClose(_ menu: NSMenu) {
    isMenuOpen = false
    guard let action = pendingAfterMenuAction else { return }
    pendingAfterMenuAction = nil
    Task { @MainActor in
      await action()
    }
  }

  private func syncBackendMenuStates() {
    backendGeminiItem?.state = settings.provider == .gemini ? .on : .off
    backendOpenRouterItem?.state = settings.provider == .openRouter ? .on : .off
    setGeminiKeyItem?.isEnabled = settings.provider == .gemini
    setGeminiModelItem?.isEnabled = settings.provider == .gemini
    detectGeminiModelItem?.isEnabled = settings.provider == .gemini
    setOpenRouterKeyItem?.isEnabled = settings.provider == .openRouter
    setOpenRouterModelItem?.isEnabled = settings.provider == .openRouter
    detectOpenRouterModelItem?.isEnabled = settings.provider == .openRouter
    if settings.provider == .gemini {
      statusItem.button?.toolTip = "\(appDisplayName) (Gemini: \(settings.geminiModel))"
    } else if settings.provider == .openRouter {
      statusItem.button?.toolTip = "\(appDisplayName) (OpenRouter: \(settings.openRouterModel))"
    } else {
      statusItem.button?.toolTip = appDisplayName
    }
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

  private func persistSettings() {
    do {
      try Settings.save(settings)
    } catch {
      NSLog("[TextPolish] Failed to save settings: \(error)")
    }
  }

  private func keychainLabel(for account: String) -> String? {
    switch account {
    case keychainAccountGemini:
      return "\(expectedAppName) — Gemini API Key"
    case keychainAccountOpenRouter:
      return "\(expectedAppName) — OpenRouter API Key"
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
    correctionController?.updateCorrector(CorrectorFactory.make(settings: settings))
    correctionController?.updateTimings(.init(settings: settings))
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

  private func recoverFromError(_ error: Error) async -> String? {
    switch settings.provider {
    case .gemini:
      guard let geminiError = error as? GeminiCorrector.GeminiError else { return nil }
      guard case .requestFailed(let status, _) = geminiError, status == 404 else { return nil }
      guard let apiKey = currentGeminiApiKey() else { return nil }

      do {
        let models = try await fetchGeminiModels(apiKey: apiKey)
        guard let chosenRaw = chooseGeminiModel(from: models) else { return nil }
        let chosen = normalizeGeminiModel(chosenRaw)
        let current = normalizeGeminiModel(settings.geminiModel)
        guard !chosen.isEmpty, chosen != current else { return nil }

        settings.geminiModel = chosen
        persistSettings()
        syncBackendMenuStates()
        refreshCorrector()
        return "Gemini model auto-detected: \(chosen)"
      } catch {
        NSLog("[TextPolish] Auto-detect Gemini model failed: \(error)")
        return nil
      }
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
        syncBackendMenuStates()
        refreshCorrector()
        return preferFree ? "OpenRouter switched to a working free model: \(chosen)" : "OpenRouter model auto-detected: \(chosen)"
      } catch {
        NSLog("[TextPolish] Auto-detect OpenRouter model failed: \(error)")
        return nil
      }
    }
  }

  private func setupHotKeys() {
    hotKeyManager.onHotKey = { [weak self] id in
      guard let self else { return }
      self.captureFrontmostApplication()
      switch id {
      case HotKeyManager.HotKeyID.correctSelection.rawValue:
        self.correctionController?.correctSelection(targetApplication: self.lastTargetApplication)
      case HotKeyManager.HotKeyID.correctAll.rawValue:
        self.correctionController?.correctAll(targetApplication: self.lastTargetApplication)
      default:
        break
      }
    }

    do {
      try hotKeyManager.registerHotKeys(
        correctSelection: settings.hotKeyCorrectSelection,
        correctAll: settings.hotKeyCorrectAll
      )
    } catch {
      NSLog("[TextPolish] Failed to register hotkeys: \(error)")
    }
  }

  @objc private func correctSelection() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      self.correctionController?.correctSelection(targetApplication: self.lastTargetApplication)
    }
  }

  @objc private func correctAll() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      self.correctionController?.correctAll(targetApplication: self.lastTargetApplication)
    }
  }

  @objc private func selectGeminiBackend() {
    settings.provider = .gemini
    persistSettings()
    syncBackendMenuStates()
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

  @objc private func selectOpenRouterBackend() {
    settings.provider = .openRouter
    persistSettings()
    syncBackendMenuStates()
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
          self.syncBackendMenuStates()
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
          self.syncBackendMenuStates()
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
          self.syncBackendMenuStates()
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
          self.syncBackendMenuStates()
          self.feedback?.showInfo("OpenRouter key saved")
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
      self.syncBackendMenuStates()
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
      self.syncBackendMenuStates()
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
      "2) Set an API key: Backend → Set Gemini API Key… or Set OpenRouter API Key…",
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
    alert.addButton(withTitle: "Reveal App")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      revealAppInFinder()
    }
  }

  private func detectGeminiModelAsync() async {
    guard let apiKey = currentGeminiApiKey() else {
      showSimpleAlert(title: "Missing Gemini API Key", message: "Set it via Backend → Set Gemini API Key…")
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
      syncBackendMenuStates()
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
      showSimpleAlert(title: "Missing OpenRouter API Key", message: "Set it via Backend → Set OpenRouter API Key…")
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
      syncBackendMenuStates()
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
      let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let message, !message.isEmpty { return message }
    }

    if let string = String(data: data, encoding: .utf8) {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return nil }
      return String(trimmed.prefix(240))
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

    let message = parseOpenRouterErrorMessage(data: data)
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

  @objc private func revealAppInFinder() {
    runAfterMenuDismissed {
      NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
  }

  @objc private func showPrivacy() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let destination: String
      let destinationURL: String
      switch self.settings.provider {
      case .gemini:
        destination = "Gemini (Google) — \(self.settings.geminiModel)"
        destinationURL = self.settings.geminiBaseURL
      case .openRouter:
        destination = "OpenRouter — \(self.settings.openRouterModel)"
        destinationURL = self.settings.openRouterBaseURL
      }

      let settingsPath = Settings.settingsFileURL().path

      let message = [
        "What happens when you correct text:",
        "• Copies your selected text (or Select All) to the clipboard temporarily",
        "• Sends that text to the selected backend to fix grammar/typos",
        "• Pastes the corrected text back",
        "• Restores your original clipboard",
        "",
        "What gets sent:",
        "• Only the text you selected / the current input text",
        "",
        "Where it is sent (over HTTPS):",
        "• \(destination)",
        "• \(destinationURL)",
        "",
        "What is stored locally:",
        "• API keys: macOS Keychain (service: \(self.keychainService))",
        "• Settings: \(settingsPath)",
        "",
        "No analytics/telemetry. Requests are only made when you trigger a correction.",
        "Note: your provider may log requests per their policy.",
      ].joined(separator: "\n")

      self.showSimpleAlert(title: "\(appDisplayName) Privacy", message: message)
    }
  }

  @objc private func showAbout() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
      let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
      let header = build.isEmpty ? "\(appDisplayName) \(version)" : "\(appDisplayName) \(version) (\(build))"

      let message = [
        "Small, fast menu bar grammar/typo corrector (minimal edits, preserves formatting).",
        "",
        "Shortcuts:",
        "• Correct Selection: \(settings.hotKeyCorrectSelection.displayString)",
        "• Correct All: \(settings.hotKeyCorrectAll.displayString)",
        "",
        "Backends: Gemini + OpenRouter",
        "Requires: Accessibility permission (to send ⌘C/⌘V/⌘A).",
        "Tip: Quit from the menu bar, relaunch from Finder → Applications → \(expectedAppName).",
        "",
        "Creator: Kurniadi Ilham",
        "GitHub: github.com/kxxil01",
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
              correctAll: self.settings.hotKeyCorrectAll
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
        if HotKeyManager.checkHotKeyInUse(keyCode: newHotKey.keyCode, modifiers: newHotKey.modifiers) {
          self.showSimpleAlert(title: "Hotkey Already in Use", message: "This combination is already used by another application.")
          return
        }
        let oldHotKey = self.settings.hotKeyCorrectSelection
        self.settings.hotKeyCorrectSelection = newHotKey
        self.persistSettings()
        do {
          try self.hotKeyManager.registerHotKeys(
            correctSelection: self.settings.hotKeyCorrectSelection,
            correctAll: self.settings.hotKeyCorrectAll
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
              correctAll: self.settings.hotKeyCorrectAll
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
        if HotKeyManager.checkHotKeyInUse(keyCode: newHotKey.keyCode, modifiers: newHotKey.modifiers) {
          self.showSimpleAlert(title: "Hotkey Already in Use", message: "This combination is already used by another application.")
          return
        }
        let oldHotKey = self.settings.hotKeyCorrectAll
        self.settings.hotKeyCorrectAll = newHotKey
        self.persistSettings()
        do {
          try self.hotKeyManager.registerHotKeys(
            correctSelection: self.settings.hotKeyCorrectSelection,
            correctAll: self.settings.hotKeyCorrectAll
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

  @objc private func resetHotKeys() {
    runAfterMenuDismissed { [weak self] in
      guard let self else { return }
      self.settings.hotKeyCorrectSelection = .correctSelectionDefault
      self.settings.hotKeyCorrectAll = .correctAllDefault
      self.persistSettings()
      do {
        try self.hotKeyManager.registerHotKeys(
          correctSelection: self.settings.hotKeyCorrectSelection,
          correctAll: self.settings.hotKeyCorrectAll
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

    selectionItem?.title = "Correct Selection"
    selectionItem?.keyEquivalent = Settings.HotKey.keyEquivalentString(keyCode: selectionHotKey.keyCode)
    selectionItem?.keyEquivalentModifierMask = Settings.HotKey.modifierMask(modifiers: selectionHotKey.modifiers)

    allItem?.title = "Correct All"
    allItem?.keyEquivalent = Settings.HotKey.keyEquivalentString(keyCode: allHotKey.keyCode)
    allItem?.keyEquivalentModifierMask = Settings.HotKey.modifierMask(modifiers: allHotKey.modifiers)
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
