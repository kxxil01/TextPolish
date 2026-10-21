import AppKit
import Carbon
import ServiceManagement
import Sparkle

// Legacy hotspot: split this up before removing the suppression.
// swiftlint:disable file_length

@MainActor
// swiftlint:disable:next type_body_length
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hotKeyManager = HotKeyManager()
    static let apiKeyPromptMessage = "Stored securely in Keychain. Key is visible while editing; "
        + "it is stored securely. Leave blank and click Clear to remove."

    private var baseImage: NSImage?
    var settings = Settings.loadOrCreateDefault()
    private var correctionController: CorrectionController?
    private var toneAnalysisController: ToneAnalysisController?
    private var toneResultWindow: ToneAnalysisResultWindow?
    var diagnosticsWindow: DiagnosticsWindow?
    var feedback: StatusItemFeedback?
    private var statusMenu: NSMenu?
    private var lastTargetApplication: NSRunningApplication?
    private var workspaceActivationObserver: Any?
    private var midnightRefreshTimer: Timer?
    private var hotKeyPressDebouncer = HotKeyPressDebouncer(cooldown: .milliseconds(350))
    private var isMenuOpen = false
    private var pendingAfterMenuAction: (@MainActor () async -> Void)?
    private var settingsWindowController: SettingsWindowController?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private var polishItem: NSMenuItem?
    private var polishStyleItems: [NSMenuItem] = []
    private var polishStyleMenu: NSMenu?
    private let polishReviewPanel = PolishReviewPanel()
    private let learnPanel = LearnPanel()
    private let lessonHistory = LessonHistory()
    private var lessonsWindow: LessonsWindow?
    private var recentLessonsItem: NSMenuItem?
    private var polishUndoer: PolishUndoer?
    private var undoItem: NSMenuItem?
    private var explanationTask: Task<Void, Never>?
    private var appPolishStyleItems: [NSMenuItem] = []
    private var appPolishStyleTarget: (bundleID: String, name: String)?
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

    let keychainAccountGemini = "geminiApiKey"
    let keychainAccountOpenRouter = "openRouterApiKey"
    let keychainAccountOpenAI = "openAIApiKey"
    let keychainAccountAnthropic = "anthropicApiKey"
    var keychainService: String {
        Keychain.primaryService(bundleIdentifier: Bundle.main.bundleIdentifier)
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
        statusItem.button?.title = StatusItemCountFormatter.title(for: todayCorrectionCount + todayToneAnalysisCount)
        statusItem.button?.toolTip = buildStatusBarToolTip()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let feedback = StatusItemFeedback(statusItem: statusItem, baseImage: initialIcon)
        self.feedback = feedback
        polishUndoer = PolishUndoer(feedback: feedback)
        correctionController = makeCorrectionController(feedback: feedback)

        let toneResultWindow = ToneAnalysisResultWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
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
            operationTimeout: toneOperationTimeoutDuration(),
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
                guard let self, !self.suppressSettingsNotification else { return }
                self.settings = newSettings
                self.refreshCorrector()
                self.setupHotKeys()
                self.syncHotKeyMenuItems()
                self.updateStatusBarToolTip()
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
        if isUpdaterAvailable {
            do {
                try updaterController.updater.start()
                updaterController.updater.automaticallyChecksForUpdates = true
                TPLogger.log("Auto-update enabled, interval: \(updaterController.updater.updateCheckInterval)s")
            } catch {
                TPLogger.log("Sparkle failed to start: \(error.localizedDescription)")
            }
        } else {
            TPLogger.log("Auto-update disabled (missing SUFeedURL or SUPublicEDKey)")
        }
        scheduleNextDailyReset()
        maybeShowWelcome()
    }

    private func makeCorrectionController(feedback: StatusItemFeedback) -> CorrectionController {
        CorrectionController(
            corrector: CorrectorFactory.make(settings: settings),
            feedback: feedback,
            settings: settings,
            timings: .init(settings: settings),
            operationTimeout: correctionOperationTimeoutDuration(),
            recoverer: { [weak self] error in
                guard let self else { return nil }
                return await self.recoverFromError(error)
            },
            shouldAttemptFallback: { [weak self] error in
                guard let self else { return false }
                return self.shouldAttemptFallback(for: error)
            },
            selectionStateProvider: { SelectionProbe.state(forProcess: $0) },
            reviewer: polishReviewPanel,
            onSuccess: { [weak self] in
                self?.incrementCorrectionCount()
            },
            onPolished: { [weak self] record in
                self?.polishUndoer?.record(record)
                self?.explainChangesIfLearning(original: record.original, polished: record.polished)
            }
        )
    }

    @objc private func statusItemClicked(_: Any?) {
        captureFrontmostApplication()
        syncAppPolishStyleItems()
        syncRecentLessonsItem()
        syncUndoItem()
        refreshCorrectionCountIfNewDay()
        refreshToneAnalysisCountIfNewDay()
        updateStatusItemIcon()
        syncUpdateMenuItems()
        guard let statusMenu, let button = statusItem.button else { return }
        button.highlight(true)
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        button.highlight(false)
    }

    @objc private func diagnosticsDidUpdate() {
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

        // Actions
        let polishItem = NSMenuItem(
            title: "Polish",
            action: #selector(polish),
            keyEquivalent: ""
        )
        polishItem.target = self
        polishItem.toolTip = "Polishes the selected text, or the whole field if nothing is selected"

        let polishStyleItem = NSMenuItem(title: "Polish Style", action: nil, keyEquivalent: "")
        let polishStyleMenu = NSMenu()
        polishStyleItems = Settings.PolishStyle.allCases.enumerated().map { index, style in
            let item = NSMenuItem(title: style.displayName, action: #selector(selectPolishStyle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            polishStyleMenu.addItem(item)
            return item
        }
        polishStyleItem.submenu = polishStyleMenu
        self.polishStyleMenu = polishStyleMenu

        let analyzeToneItem = NSMenuItem(
            title: "Analyze Tone",
            action: #selector(analyzeTone),
            keyEquivalent: ""
        )
        analyzeToneItem.target = self

        self.polishItem = polishItem
        self.analyzeToneItem = analyzeToneItem

        let undoItem = NSMenuItem(title: "Undo Last Polish", action: nil, keyEquivalent: "")
        undoItem.target = self
        undoItem.toolTip = "Puts back the text from before the last Polish, if it is still unchanged"
        self.undoItem = undoItem

        menu.addItem(polishItem)
        menu.addItem(polishStyleItem)
        menu.addItem(undoItem)
        menu.addItem(analyzeToneItem)

        let cancelItem = NSMenuItem(
            title: "Cancel Active Operation",
            action: #selector(cancelActiveOperation),
            keyEquivalent: ""
        )
        cancelItem.target = self
        cancelCorrectionItem = cancelItem
        menu.addItem(cancelItem)
        menu.addItem(.separator())

        // Info & tools
        let recentLessonsItem = NSMenuItem(title: "Recent Lessons\u{2026}", action: nil, keyEquivalent: "")
        recentLessonsItem.target = self
        recentLessonsItem.toolTip = "Explanations from Learn mode, saved on this Mac"
        self.recentLessonsItem = recentLessonsItem
        menu.addItem(recentLessonsItem)
        syncRecentLessonsItem()

        let diagnosticsItem = NSMenuItem(
            title: "Diagnostics\u{2026}",
            action: #selector(openDiagnostics),
            keyEquivalent: ""
        )
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

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

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings\u{2026}",
            action: #selector(openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        statusMenu = menu
        syncHotKeyMenuItems()
        syncCancelMenuState()
        syncUpdateMenuItems()
    }

    func menuWillOpen(_: NSMenu) {
        isMenuOpen = true
        syncCancelMenuState()
    }

    func menuDidClose(_: NSMenu) {
        isMenuOpen = false
        guard let action = pendingAfterMenuAction else { return }
        pendingAfterMenuAction = nil
        Task { @MainActor in
            await action()
        }
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

    private var suppressSettingsNotification = false

    func applySettingsMutation(_ mutate: (inout Settings) -> Void) {
        var latest = Settings.loadOrCreateDefault()
        mutate(&latest)
        latest.normalizeRuntimeValues()
        do {
            suppressSettingsNotification = true
            try Settings.saveAndNotify(latest)
            settings = latest
            suppressSettingsNotification = false
        } catch {
            suppressSettingsNotification = false
            TPLogger.log("Failed to save settings: \(error)")
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
        scheduleNextDailyReset()
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
        scheduleNextDailyReset()
    }

    private func formattedToday() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func updateStatusItemIcon() {
        let count = todayCorrectionCount + todayToneAnalysisCount
        let icon = makeIconWithBadge(count: count)
        statusItem.button?.image = icon
        let title = StatusItemCountFormatter.title(for: count)
        statusItem.button?.title = title
        feedback?.updateBaseImage(icon)
        feedback?.updateBaseTitle(title)
    }

    private func makeIconWithBadge(count _: Int) -> NSImage? {
        guard let base = baseImage else { return nil }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private func scheduleNextDailyReset(now: Date = Date(), calendar: Calendar = .current) {
        midnightRefreshTimer?.invalidate()
        let nextResetDate = DailyResetScheduler.nextResetDate(after: now, calendar: calendar)
        midnightRefreshTimer = Timer(
            fireAt: nextResetDate,
            interval: 0,
            target: self,
            selector: #selector(handleDailyResetTimer),
            userInfo: nil,
            repeats: false
        )
        if let midnightRefreshTimer {
            RunLoop.main.add(midnightRefreshTimer, forMode: .common)
        }
    }

    @objc private func handleDailyResetTimer() {
        refreshCorrectionCountIfNewDay()
        refreshToneAnalysisCountIfNewDay()
        updateStatusItemIcon()
        scheduleNextDailyReset()
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

    func setKeychainPassword(_ password: String, service: String, account: String) async throws {
        TPLogger.log("Keychain set start account=\(account)")
        NSApp.activate(ignoringOtherApps: true)
        let label = keychainLabel(for: account)
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Keychain.setConfiguredPassword(
                        password,
                        primaryService: service,
                        account: account,
                        label: label
                    )
                    TPLogger.log("Keychain set success account=\(account)")
                    continuation.resume()
                } catch {
                    TPLogger.log("Keychain set failed account=\(account) error=\(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteKeychainPassword(service: String, account: String) async throws {
        TPLogger.log("Keychain delete start account=\(account)")
        NSApp.activate(ignoringOtherApps: true)
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Keychain.deleteConfiguredPassword(primaryService: service, account: account)
                    TPLogger.log("Keychain delete success account=\(account)")
                    continuation.resume()
                } catch {
                    TPLogger.log("Keychain delete failed account=\(account) error=\(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func refreshCorrector() {
        correctionController?.updateSettings(settings)
        correctionController?.updateCorrector(CorrectorFactory.make(settings: settings))
        correctionController?.updateTimings(.init(settings: settings))
        correctionController?.updateOperationTimeout(correctionOperationTimeoutDuration())
        toneAnalysisController?.updateAnalyzer(ToneAnalyzerFactory.make(settings: settings))
        toneAnalysisController?.updateTimings(.init(settings: settings))
        toneAnalysisController?.updateOperationTimeout(toneOperationTimeoutDuration())
    }

    private func correctionOperationTimeoutDuration() -> Duration {
        let requestSeconds = max(1, Int(ceil(settings.requestTimeoutSeconds)))
        let timeoutSeconds = min(30, max(12, requestSeconds + 4))
        return .seconds(timeoutSeconds)
    }

    private func toneOperationTimeoutDuration() -> Duration {
        let requestSeconds = max(1, Int(ceil(settings.requestTimeoutSeconds)))
        let timeoutSeconds = min(25, max(8, requestSeconds + 2))
        return .seconds(timeoutSeconds)
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

    private func toneTimingsOverride(for app: NSRunningApplication?) -> ToneAnalysisController.Timings? {
        guard let correctionTimings = timingsOverride(for: app) else { return nil }
        return ToneAnalysisController.Timings(
            activationDelay: correctionTimings.activationDelay,
            copySettleDelay: correctionTimings.copySettleDelay,
            copyTimeout: correctionTimings.copyTimeout
        )
    }

    func runAfterMenuDismissed(_ action: @escaping @MainActor () async -> Void) {
        if isMenuOpen {
            pendingAfterMenuAction = action
            return
        }
        Task { @MainActor in
            await action()
        }
    }

    private func setupHotKeys() {
        hotKeyManager.onHotKey = { [weak self] id in
            guard let self else { return }
            _ = self.handleRegisteredHotKey(id)
        }

        do {
            try hotKeyManager.registerHotKeys(
                polish: settings.hotKeyPolish,
                analyzeTone: settings.hotKeyAnalyzeTone,
                styles: styleHotKeysByID()
            )
        } catch {
            TPLogger.log("Failed to register hotkeys: \(error)")
            let styleShortcuts = Settings.PolishStyle.allCases.compactMap { style in
                settings.styleHotKey(for: style).map { "Polish as \(style.displayName) \($0.displayString)" }
            }
            let configured = ([
                "Polish \(settings.hotKeyPolish.displayString)",
                "Analyze Tone \(settings.hotKeyAnalyzeTone.displayString)",
            ] + styleShortcuts).joined(separator: " • ")
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            feedback?.showError("Some shortcuts could not be registered. \(message) Configured: \(configured)")
        }
    }

    private func styleHotKeysByID() -> [Int: Settings.HotKey] {
        var result: [Int: Settings.HotKey] = [:]
        for (index, style) in Settings.PolishStyle.allCases.enumerated() {
            if let hotKey = settings.styleHotKey(for: style) {
                result[HotKeyManager.styleHotKeyID(index: index)] = hotKey
            }
        }
        return result
    }

    @discardableResult
    private func handleRegisteredHotKey(
        _ id: Int,
        now: ContinuousClock.Instant = ContinuousClock.now
    ) -> Bool {
        guard hotKeyPressDebouncer.shouldAccept(id: id, now: now) else {
            return false
        }

        captureFrontmostApplication()
        let target = lastTargetApplication
        let correctionTimings = timingsOverride(for: target)
        let toneTimings = toneTimingsOverride(for: target)

        switch id {
        case HotKeyManager.HotKeyID.polish.rawValue:
            correctionController?.polish(
                style: settings.polishStyle(forApp: target?.bundleIdentifier).correctionStyle,
                targetApplication: target,
                timingsOverride: correctionTimings
            )
        case HotKeyManager.HotKeyID.analyzeTone.rawValue:
            toneAnalysisController?.analyzeSelection(targetApplication: target, timingsOverride: toneTimings)
        default:
            // A style shortcut polishes in that style, whatever style the app normally uses.
            let styles = Settings.PolishStyle.allCases
            guard let index = HotKeyManager.styleIndex(forHotKeyID: id), styles.indices.contains(index) else {
                return false
            }
            correctionController?.polish(
                style: styles[index].correctionStyle,
                targetApplication: target,
                timingsOverride: correctionTimings
            )
        }

        return true
    }

    @objc private func polish() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            let target = self.lastTargetApplication
            let timings = self.timingsOverride(for: target)
            self.correctionController?.polish(
                style: self.settings.polishStyle(forApp: target?.bundleIdentifier).correctionStyle,
                targetApplication: target,
                timingsOverride: timings
            )
        }
    }

    @objc private func selectPolishStyle(_ sender: NSMenuItem) {
        let styles = Settings.PolishStyle.allCases
        guard styles.indices.contains(sender.tag) else { return }
        applySettingsMutation { $0.polishStyle = styles[sender.tag] }
        syncHotKeyMenuItems()
    }

    /// Learn mode: asks the current provider why the main changes were made and shows them without taking focus.
    private func explainChangesIfLearning(original: String, polished: String) {
        guard settings.learnMode, let explainer = CorrectorFactory.make(settings: settings) as? ChangeExplaining else {
            return
        }
        explanationTask?.cancel()
        explanationTask = Task { [weak self] in
            do {
                let lines = try await explainer.explainChanges(original: original, polished: polished)
                guard !Task.isCancelled, let self else { return }
                TPLogger.log("Learn: \(lines.count) explanations")
                self.learnPanel.show(lines: lines)
                self.lessonHistory.add(lines)
                self.lessonsWindow?.reload()
                self.syncRecentLessonsItem()
            } catch {
                TPLogger.log("Learn explanation failed: \(error)")
            }
        }
    }

    @objc private func selectAppPolishStyle(_ sender: NSMenuItem) {
        guard let bundleID = appPolishStyleTarget?.bundleID else { return }
        let styles = Settings.PolishStyle.allCases
        // Tags index into the styles; the Default item has no style and clears the app's choice.
        let chosen = styles.indices.contains(sender.tag) ? styles[sender.tag] : nil
        applySettingsMutation { $0.appPolishStyles[bundleID] = chosen }
        syncHotKeyMenuItems()
    }

    /// Shows a section for the app Polish will act on, so its style can differ from the default.
    private func syncAppPolishStyleItems() {
        appPolishStyleTarget = lastTargetApplication.flatMap { app in
            app.bundleIdentifier.map { (bundleID: $0, name: app.localizedName ?? $0) }
        }
        rebuildAppPolishStyleItems()
    }

    private func rebuildAppPolishStyleItems() {
        guard let polishStyleMenu else { return }
        appPolishStyleItems.forEach(polishStyleMenu.removeItem)
        appPolishStyleItems = []
        guard let target = appPolishStyleTarget else { return }

        let chosen = settings.appPolishStyles[target.bundleID]
        let header = NSMenuItem(title: "In \(target.name)", action: nil, keyEquivalent: "")
        let defaultStyle = settings.defaultPolishStyle(forApp: target.bundleID)
        let useDefault = NSMenuItem(
            title: "Default (\(defaultStyle.displayName))",
            action: #selector(selectAppPolishStyle(_:)),
            keyEquivalent: ""
        )
        useDefault.tag = -1
        useDefault.state = chosen == nil ? .on : .off
        var choices = [useDefault]
        for (index, style) in Settings.PolishStyle.allCases.enumerated() {
            let item = NSMenuItem(title: style.displayName, action: #selector(selectAppPolishStyle(_:)), keyEquivalent: "")
            item.tag = index
            item.state = chosen == style ? .on : .off
            choices.append(item)
        }
        for item in choices {
            item.target = self
            item.indentationLevel = 1
        }
        appPolishStyleItems = [.separator(), header] + choices
        appPolishStyleItems.forEach(polishStyleMenu.addItem)
    }

    @objc private func cancelActiveOperation() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            let didCancelCorrection = self.correctionController?.cancelCurrentCorrection() == true
            let didCancelTone = self.toneAnalysisController?.cancelCurrentAnalysis() == true
            if didCancelCorrection || didCancelTone {
                self.feedback?.showInfo("Canceling...")
            } else {
                self.feedback?.showInfo("No operation in progress")
            }
        }
    }

    @objc private func analyzeTone() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            let target = self.lastTargetApplication
            let toneTimings = self.toneTimingsOverride(for: target)
            self.toneAnalysisController?.analyzeSelection(targetApplication: target, timingsOverride: toneTimings)
        }
    }

    func applyFallbackSettingToggle() {
        applySettingsMutation { $0.enableGeminiOpenRouterFallback.toggle() }
        refreshCorrector()
    }

    @objc private func openSettingsWindow(_: Any?) {
        if let existing = settingsWindowController, existing.window?.isVisible == true {
            // Window already open — bring it to front and reload to show latest state
            existing.viewController?.loadSettings()
            existing.window?.makeKeyAndOrderFront(nil)
        } else {
            settingsWindowController = SettingsWindowController(keychainServiceOverride: nil)
            settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Enabled once a Polish has changed some text that Undo can find again.
    private func syncUndoItem() {
        undoItem?.action = polishUndoer?.canUndo == true ? #selector(undoLastPolish) : nil
    }

    @objc private func undoLastPolish() {
        runAfterMenuDismissed { [weak self] in
            guard let self, let undoer = self.polishUndoer else { return }
            guard self.correctionController?.isBusy != true else {
                self.feedback?.showInfo("Polish is still running")
                return
            }
            await undoer.undo()
            self.syncUndoItem()
        }
    }

    /// Disabled until Learn mode has saved a lesson; a menu item without an action is shown disabled.
    private func syncRecentLessonsItem() {
        recentLessonsItem?.action = lessonHistory.lessons.isEmpty ? nil : #selector(showRecentLessons)
    }

    @objc private func showRecentLessons() {
        runAfterMenuDismissed { [weak self] in
            guard let self else { return }
            if self.lessonsWindow == nil {
                self.lessonsWindow = LessonsWindow(history: self.lessonHistory)
            }
            self.lessonsWindow?.show()
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
            "2) Set an API key: Provider → Set Gemini API Key… or Set OpenRouter API Key…",
            "",
            "Shortcuts:",
            "• Polish (selection, or the whole field): \(settings.hotKeyPolish.displayString)",
            "• Analyze Tone: \(settings.hotKeyAnalyzeTone.displayString)",
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
            } else if settings.provider == .openAI {
                setOpenAIApiKey()
            } else if settings.provider == .anthropic {
                setAnthropicApiKey()
            } else {
                setGeminiApiKey()
            }
        default:
            break
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func syncHotKeyMenuItems() {
        let polishHotKey = settings.hotKeyPolish
        let analyzeToneHotKey = settings.hotKeyAnalyzeTone

        polishItem?.title = "Polish"
        polishItem?.keyEquivalent = Settings.HotKey.keyEquivalentString(keyCode: polishHotKey.keyCode)
        polishItem?.keyEquivalentModifierMask = Settings.HotKey.modifierMask(modifiers: polishHotKey.modifiers)

        for (index, style) in Settings.PolishStyle.allCases.enumerated() where polishStyleItems.indices.contains(index) {
            polishStyleItems[index].state = settings.polishStyle == style ? .on : .off
        }
        rebuildAppPolishStyleItems()

        analyzeToneItem?.title = "Analyze Tone"
        analyzeToneItem?.keyEquivalent = Settings.HotKey.keyEquivalentString(keyCode: analyzeToneHotKey.keyCode)
        analyzeToneItem?.keyEquivalentModifierMask = Settings.HotKey.modifierMask(modifiers: analyzeToneHotKey.modifiers)
    }

    private func syncCancelMenuState() {
        cancelCorrectionItem?.isEnabled =
            correctionController?.isBusy == true || toneAnalysisController?.isBusy == true
    }

    /// Builds a tooltip string showing the app name and active provider/model.
    private func buildStatusBarToolTip() -> String {
        let providerName: String
        let model: String
        switch settings.provider {
        case .gemini:
            providerName = "Gemini"
            model = settings.geminiModel
        case .openRouter:
            providerName = "OpenRouter"
            model = settings.openRouterModel
        case .openAI:
            providerName = "OpenAI"
            model = settings.openAIModel
        case .anthropic:
            providerName = "Anthropic"
            model = settings.anthropicModel
        }
        return "\(appDisplayName) (\(providerName): \(model))"
    }

    /// Updates the status bar tooltip to reflect the current provider/model.
    /// Called on settings change so users hovering the menu bar icon see accurate info.
    private func updateStatusBarToolTip() {
        let toolTip = buildStatusBarToolTip()
        statusItem.button?.toolTip = toolTip
        feedback?.updateBaseToolTip(toolTip)
    }

}

#if DEBUG
    extension AppDelegate {
        func debugFinishLaunching() {
            applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        }

        var debugCorrectionOperationTimeout: Duration? {
            correctionController?.debugOperationTimeout
        }

        var debugToneOperationTimeout: Duration? {
            toneAnalysisController?.debugOperationTimeout
        }

        var debugHasMidnightRefreshTimer: Bool {
            midnightRefreshTimer != nil
        }

        var debugStatusItemTitle: String? {
            statusItem.button?.title
        }

        var debugPolishMenuShortcut: (String, NSEvent.ModifierFlags)? {
            guard let polishItem else { return nil }
            return (polishItem.keyEquivalent, polishItem.keyEquivalentModifierMask)
        }

        var debugSelectedPolishStyleTitle: String? {
            polishStyleItems.first { $0.state == .on }?.title
        }

        var debugUndoEnabled: Bool {
            undoItem?.action != nil
        }

        func debugRecordPolish(_ record: PolishRecord) {
            polishUndoer?.record(record)
            syncUndoItem()
        }

        var debugRecentLessonsEnabled: Bool {
            recentLessonsItem?.action != nil
        }

        func debugRecordLesson(_ lines: [String]) {
            lessonHistory.add(lines)
            syncRecentLessonsItem()
        }

        func debugShowAppPolishStyles(bundleID: String, name: String) {
            appPolishStyleTarget = (bundleID: bundleID, name: name)
            rebuildAppPolishStyleItems()
        }

        /// Titles of the per-app section, with a check mark on the chosen item.
        var debugAppPolishStyleTitles: [String] {
            appPolishStyleItems.filter { !$0.isSeparatorItem }.map { $0.state == .on ? "✓ \($0.title)" : $0.title }
        }

        func debugSelectAppPolishStyle(title: String) {
            guard let item = appPolishStyleItems.first(where: { $0.title == title }) else { return }
            selectAppPolishStyle(item)
        }

        @discardableResult
        func debugHandleRegisteredHotKey(_ id: Int, now: ContinuousClock.Instant) -> Bool {
            handleRegisteredHotKey(id, now: now)
        }
    }
#endif

extension AppDelegate: SPUUpdaterDelegate {
    nonisolated func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
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

    nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
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

    nonisolated func updater(_: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
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
