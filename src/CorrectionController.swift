import AppKit

struct FeedbackCooldown: Sendable {
  private var lastShown: ContinuousClock.Instant?
  let cooldown: Duration

  init(cooldown: Duration) {
    self.cooldown = cooldown
  }

  mutating func shouldShow(now: ContinuousClock.Instant) -> Bool {
    if let lastShown, now < lastShown + cooldown {
      return false
    }
    self.lastShown = now
    return true
  }
}

#if DEBUG
extension CorrectionController {
  var debugOperationTimeout: Duration {
    operationTimeout
  }
}
#endif

@MainActor
final class CorrectionController {
  typealias GlobalKeyMonitorInstaller = (@escaping (UInt16, NSEvent.ModifierFlags) -> Void) -> Any?
  typealias LocalKeyMonitorInstaller = (@escaping (UInt16, NSEvent.ModifierFlags) -> Bool) -> Any?
  typealias EventMonitorRemover = (Any) -> Void

  private enum OperationError: LocalizedError {
    case timedOut(Duration)
    case clipboardChanged
    case targetApplicationChanged

    var errorDescription: String? {
      switch self {
      case .timedOut(let timeout):
        let seconds = max(1, Int(timeout.components.seconds))
        return "Correction timed out after \(seconds) seconds"
      case .clipboardChanged:
        return "Clipboard changed during correction before paste"
      case .targetApplicationChanged:
        return "Target app changed before corrected text could be pasted"
      }
    }
  }

  struct RecoveryAction: Sendable {
    let message: String
    let corrector: GrammarCorrector?
  }

  struct Timings: Sendable {
    let activationDelay: Duration
    let selectAllDelay: Duration
    let copySettleDelay: Duration
    let copyTimeout: Duration
    let pasteSettleDelay: Duration
    let postPasteDelay: Duration

    static let `default` = Timings(
      activationDelay: .milliseconds(80),
      selectAllDelay: .milliseconds(60),
      copySettleDelay: .milliseconds(20),
      copyTimeout: .milliseconds(900),
      pasteSettleDelay: .milliseconds(25),
      postPasteDelay: .milliseconds(180)
    )

    init(
      activationDelay: Duration,
      selectAllDelay: Duration,
      copySettleDelay: Duration,
      copyTimeout: Duration,
      pasteSettleDelay: Duration,
      postPasteDelay: Duration
    ) {
      self.activationDelay = activationDelay
      self.selectAllDelay = selectAllDelay
      self.copySettleDelay = copySettleDelay
      self.copyTimeout = copyTimeout
      self.pasteSettleDelay = pasteSettleDelay
      self.postPasteDelay = postPasteDelay
    }

    init(settings: Settings) {
      activationDelay = Timings.duration(milliseconds: settings.activationDelayMilliseconds)
      selectAllDelay = Timings.duration(milliseconds: settings.selectAllDelayMilliseconds)
      copySettleDelay = Timings.duration(milliseconds: settings.copySettleDelayMilliseconds)
      copyTimeout = Timings.duration(milliseconds: settings.copyTimeoutMilliseconds)
      pasteSettleDelay = Timings.duration(milliseconds: settings.pasteSettleDelayMilliseconds)
      postPasteDelay = Timings.duration(milliseconds: settings.postPasteDelayMilliseconds)
    }

    static func duration(milliseconds value: Int) -> Duration {
      .milliseconds(Int64(max(0, value)))
    }

    func applying(_ profile: Settings.TimingProfile) -> Timings {
      Timings(
        activationDelay: profile.activationDelayMilliseconds.map(Timings.duration) ?? activationDelay,
        selectAllDelay: profile.selectAllDelayMilliseconds.map(Timings.duration) ?? selectAllDelay,
        copySettleDelay: profile.copySettleDelayMilliseconds.map(Timings.duration) ?? copySettleDelay,
        copyTimeout: profile.copyTimeoutMilliseconds.map(Timings.duration) ?? copyTimeout,
        pasteSettleDelay: profile.pasteSettleDelayMilliseconds.map(Timings.duration) ?? pasteSettleDelay,
        postPasteDelay: profile.postPasteDelayMilliseconds.map(Timings.duration) ?? postPasteDelay
      )
    }
  }

  private var corrector: GrammarCorrector
  private let feedback: FeedbackPresenter
  private let keyboard: KeyboardControlling
  private let pasteboard: PasteboardControlling
  private var settings: Settings
  private let recoverer: (@MainActor (Error) async -> RecoveryAction?)?
  private let shouldAttemptFallback: (@MainActor (Error) -> Bool)?
  private let fallbackCorrectorFactory: (@MainActor () -> GrammarCorrector?)?
  private let addGlobalKeyMonitor: GlobalKeyMonitorInstaller
  private let addLocalKeyMonitor: LocalKeyMonitorInstaller
  private let removeEventMonitor: EventMonitorRemover
  private let onSuccess: (@MainActor () -> Void)?

  private var timings: Timings
  private var operationTimeout: Duration
  private var isRunning = false
  private var currentTask: Task<Void, Never>?
  private var busyFeedbackGate = FeedbackCooldown(cooldown: .milliseconds(900))
  private nonisolated(unsafe) var globalEscapeMonitor: Any?
  private nonisolated(unsafe) var localEscapeMonitor: Any?
  private let frontmostApplicationPIDProvider: @MainActor () -> pid_t?
  private let applicationResolver: @MainActor (pid_t) -> NSRunningApplication?

  init(
    corrector: GrammarCorrector,
    feedback: FeedbackPresenter,
    settings: Settings,
    timings: Timings = .default,
    operationTimeout: Duration = .seconds(12),
    keyboard: KeyboardControlling? = nil,
    pasteboard: PasteboardControlling? = nil,
    recoverer: (@MainActor (Error) async -> RecoveryAction?)? = nil,
    shouldAttemptFallback: (@MainActor (Error) -> Bool)? = nil,
    fallbackCorrectorFactory: (@MainActor () -> GrammarCorrector?)? = nil,
    frontmostApplicationPIDProvider: (@MainActor () -> pid_t?)? = nil,
    applicationResolver: (@MainActor (pid_t) -> NSRunningApplication?)? = nil,
    addGlobalKeyMonitor: GlobalKeyMonitorInstaller? = nil,
    addLocalKeyMonitor: LocalKeyMonitorInstaller? = nil,
    removeEventMonitor: EventMonitorRemover? = nil,
    onSuccess: (@MainActor () -> Void)? = nil
  ) {
    self.corrector = corrector
    self.feedback = feedback
    self.settings = settings
    self.timings = timings
    self.operationTimeout = operationTimeout
    self.keyboard = keyboard ?? KeyboardController()
    self.pasteboard = pasteboard ?? PasteboardController()
    self.recoverer = recoverer
    self.shouldAttemptFallback = shouldAttemptFallback
    self.fallbackCorrectorFactory = fallbackCorrectorFactory
    self.frontmostApplicationPIDProvider = frontmostApplicationPIDProvider ?? {
      NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    self.applicationResolver = applicationResolver ?? { pid in
      NSWorkspace.shared.runningApplications.first { $0.processIdentifier == pid }
    }
    self.addGlobalKeyMonitor = addGlobalKeyMonitor ?? CorrectionController.defaultAddGlobalKeyMonitor
    self.addLocalKeyMonitor = addLocalKeyMonitor ?? CorrectionController.defaultAddLocalKeyMonitor
    self.removeEventMonitor = removeEventMonitor ?? CorrectionController.defaultRemoveEventMonitor
    self.onSuccess = onSuccess
  }

  func updateCorrector(_ corrector: GrammarCorrector) {
    self.corrector = corrector
  }

  func updateTimings(_ timings: Timings) {
    self.timings = timings
  }

  func updateSettings(_ settings: Settings) {
    self.settings = settings
  }

  func updateOperationTimeout(_ timeout: Duration) {
    self.operationTimeout = timeout
  }

  var isBusy: Bool {
    isRunning
  }

  @discardableResult
  func cancelCurrentCorrection() -> Bool {
    guard isRunning, let currentTask else { return false }
    currentTask.cancel()
    return true
  }

  func correctSelection(targetApplication: NSRunningApplication? = nil, timingsOverride: Timings? = nil) {
    run(mode: .selection, targetApplication: targetApplication, timingsOverride: timingsOverride)
  }

  func correctAll(targetApplication: NSRunningApplication? = nil, timingsOverride: Timings? = nil) {
    run(mode: .all, targetApplication: targetApplication, timingsOverride: timingsOverride)
  }

  private enum Mode {
    case selection
    case all
  }

  private func run(mode: Mode, targetApplication: NSRunningApplication?, timingsOverride: Timings?) {
    guard !isRunning else {
      maybeShowBusyFeedback()
      return
    }
    isRunning = true
    let corrector = corrector
    let timings = timingsOverride ?? timings
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      let operationStartedAt = Date()
      let deadline = ContinuousClock.now + self.operationTimeout
      var activeProvider = self.settings.provider
      var activeModel = self.modelName(for: activeProvider)
      var fallbackCount = 0
      var usedCorrector = corrector
      self.updateProviderModel(for: corrector, provider: &activeProvider, model: &activeModel)
      defer {
        self.isRunning = false
        self.currentTask = nil
      }

      guard self.keyboard.isAccessibilityTrusted(prompt: true) else {
        self.feedback.showError("Enable Accessibility")
        DiagnosticsStore.shared.recordFailure(
          operation: .correction,
          provider: activeProvider,
          model: activeModel,
          latencySeconds: nil,
          retryCount: 0,
          fallbackCount: 0,
          message: "Accessibility permission required",
          error: nil
        )
        return
      }

      self.installEscapeCancellationMonitors()
      defer {
        self.removeEscapeCancellationMonitorsIfNeeded()
      }

      var didPaste = false

      do {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let targetPID: pid_t? = {
          if let targetApplication, targetApplication.processIdentifier != currentPid {
            return targetApplication.processIdentifier
          }
          if let frontmostPID = self.frontmostApplicationPIDProvider(), frontmostPID != currentPid {
            return frontmostPID
          }
          return nil
        }()
        let appToActivate: NSRunningApplication? = {
          if let targetApplication, targetApplication.processIdentifier != currentPid {
            return targetApplication
          }
          guard let targetPID else { return nil }
          return self.applicationResolver(targetPID)
        }()
        if let appToActivate, !appToActivate.isActive {
          _ = appToActivate.activate(options: [])
          try await self.sleepRespectingDeadline(timings.activationDelay, until: deadline)
        }

        let snapshot = self.pasteboard.snapshot()
        var ownedClipboardChangeCount: Int?
        defer {
          if let ownedClipboardChangeCount,
             self.pasteboard.changeCount == ownedClipboardChangeCount
          {
            self.pasteboard.restore(snapshot)
          }
        }

        if mode == .all {
          self.keyboard.sendCommandA()
          try await self.sleepRespectingDeadline(timings.selectAllDelay, until: deadline)
        }

        let inputText = try await self.copySelectedText(
          timings: timings,
          deadline: deadline,
          updateOwnedClipboardChangeCount: { ownedClipboardChangeCount = $0 }
        )
        try Task.checkCancellation()
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
          self.feedback.showError("No text selected")
          DiagnosticsStore.shared.recordFailure(
            operation: .correction,
            provider: activeProvider,
            model: activeModel,
            latencySeconds: Date().timeIntervalSince(operationStartedAt),
            retryCount: 0,
            fallbackCount: fallbackCount,
            message: "No text selected",
            error: nil
          )
          return
        }

        var corrected: String?
        do {
          corrected = try await self.runCorrector(corrector, text: inputText, deadline: deadline)
        } catch {
          let primaryError = error
          var unresolvedError: Error? = primaryError

          // Check if we should try fallback provider
          if shouldAttemptFallback?(primaryError) == true,
             let fallbackCorrector = createFallbackCorrector()
          {
            self.feedback.showInfo("Primary provider failed, trying fallback provider...")
            do {
              fallbackCount += 1
              usedCorrector = fallbackCorrector
              self.updateProviderModel(for: fallbackCorrector, provider: &activeProvider, model: &activeModel)
              corrected = try await self.runCorrector(fallbackCorrector, text: inputText, deadline: deadline)
              unresolvedError = nil
            } catch {
              unresolvedError = error
            }
          }

          // Use recoverer if available
          if let unresolvedError {
            if let recoverer, let action = await recoverer(unresolvedError) {
              self.feedback.showInfo(action.message)
              let retryCorrector = action.corrector ?? self.corrector
              usedCorrector = retryCorrector
              self.updateProviderModel(for: retryCorrector, provider: &activeProvider, model: &activeModel)
              corrected = try await self.runCorrector(retryCorrector, text: inputText, deadline: deadline)
            } else {
              throw unresolvedError
            }
          }
        }
        guard let corrected else {
          throw NSError(
            domain: "TextPolish",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Correction failed before producing output"]
          )
        }
        guard corrected != inputText else {
          self.feedback.showInfo("No changes")
          let retryCount = (usedCorrector as? RetryReporting)?.lastRetryCount ?? 0
          DiagnosticsStore.shared.recordSuccess(
            operation: .correction,
            provider: activeProvider,
            model: activeModel,
            latencySeconds: Date().timeIntervalSince(operationStartedAt),
            retryCount: retryCount,
            fallbackCount: fallbackCount,
            note: "No changes"
          )
          return
        }

        try Task.checkCancellation()
        self.pasteboard.setString(corrected)
        ownedClipboardChangeCount = self.pasteboard.changeCount
        try await self.sleepRespectingDeadline(timings.pasteSettleDelay, until: deadline)
        try Task.checkCancellation()
        guard self.pasteboard.changeCount == ownedClipboardChangeCount else {
          throw OperationError.clipboardChanged
        }
        if let targetPID, self.frontmostApplicationPIDProvider() != targetPID {
          if let appToActivate = self.applicationResolver(targetPID), !appToActivate.isActive {
            _ = appToActivate.activate(options: [])
            try await self.sleepRespectingDeadline(timings.activationDelay, until: deadline)
          }
          guard self.frontmostApplicationPIDProvider() == targetPID else {
            throw OperationError.targetApplicationChanged
          }
        }
        self.keyboard.sendCommandV()
        didPaste = true
        try await self.sleepRespectingDeadline(timings.postPasteDelay, until: deadline)
        self.feedback.showSuccess()
        let retryCount = (usedCorrector as? RetryReporting)?.lastRetryCount ?? 0
        DiagnosticsStore.shared.recordSuccess(
          operation: .correction,
          provider: activeProvider,
          model: activeModel,
          latencySeconds: Date().timeIntervalSince(operationStartedAt),
          retryCount: retryCount,
          fallbackCount: fallbackCount
        )
        self.onSuccess?()
      } catch is CancellationError {
        if didPaste {
          self.feedback.showSuccess()
          let retryCount = (usedCorrector as? RetryReporting)?.lastRetryCount ?? 0
          DiagnosticsStore.shared.recordSuccess(
            operation: .correction,
            provider: activeProvider,
            model: activeModel,
            latencySeconds: Date().timeIntervalSince(operationStartedAt),
            retryCount: retryCount,
            fallbackCount: fallbackCount,
            note: "Canceled after paste"
          )
          self.onSuccess?()
        } else {
          self.feedback.showInfo("Canceled")
          let retryCount = (usedCorrector as? RetryReporting)?.lastRetryCount ?? 0
          DiagnosticsStore.shared.recordNote(
            operation: .correction,
            provider: activeProvider,
            model: activeModel,
            latencySeconds: Date().timeIntervalSince(operationStartedAt),
            retryCount: retryCount,
            fallbackCount: fallbackCount,
            message: "Canceled",
            updateHealth: false
          )
        }
      } catch {
        if didPaste, let operationError = error as? OperationError, case .timedOut = operationError {
          self.feedback.showSuccess()
          let retryCount = (usedCorrector as? RetryReporting)?.lastRetryCount ?? 0
          DiagnosticsStore.shared.recordSuccess(
            operation: .correction,
            provider: activeProvider,
            model: activeModel,
            latencySeconds: Date().timeIntervalSince(operationStartedAt),
            retryCount: retryCount,
            fallbackCount: fallbackCount,
            note: "Timed out after paste"
          )
          self.onSuccess?()
          return
        }

        let message =
          (error as? LocalizedError)?.errorDescription ??
          (error as NSError).localizedDescription
        self.feedback.showError(message)
        let retryCount = (usedCorrector as? RetryReporting)?.lastRetryCount ?? 0
        DiagnosticsStore.shared.recordFailure(
          operation: .correction,
          provider: activeProvider,
          model: activeModel,
          latencySeconds: Date().timeIntervalSince(operationStartedAt),
          retryCount: retryCount,
          fallbackCount: fallbackCount,
          message: message,
          error: error
        )
        TPLogger.log("\(error)")
      }
    }
    currentTask = task
  }

  private func installEscapeCancellationMonitors() {
    if globalEscapeMonitor == nil {
      globalEscapeMonitor = addGlobalKeyMonitor { [weak self] keyCode, modifiers in
        guard EscapeKeyCancellationMatcher.shouldCancel(keyCode: keyCode, modifiers: modifiers) else {
          return
        }
        Task { @MainActor [weak self] in
          _ = self?.cancelCurrentCorrection()
        }
      }
    }

    if localEscapeMonitor == nil {
      localEscapeMonitor = addLocalKeyMonitor { [weak self] keyCode, modifiers in
        guard EscapeKeyCancellationMatcher.shouldCancel(keyCode: keyCode, modifiers: modifiers) else {
          return false
        }
        Task { @MainActor [weak self] in
          _ = self?.cancelCurrentCorrection()
        }
        return true
      }
    }
  }

  private func removeEscapeCancellationMonitorsIfNeeded() {
    if let globalEscapeMonitor {
      removeEventMonitor(globalEscapeMonitor)
      self.globalEscapeMonitor = nil
    }

    if let localEscapeMonitor {
      removeEventMonitor(localEscapeMonitor)
      self.localEscapeMonitor = nil
    }
  }

  private func maybeShowBusyFeedback() {
    if busyFeedbackGate.shouldShow(now: ContinuousClock.now) {
      feedback.showInfo("Correction in progress")
    }
  }

  private func copySelectedText(
    timings: Timings,
    deadline: ContinuousClock.Instant,
    updateOwnedClipboardChangeCount: @escaping (Int) -> Void
  ) async throws -> String {
    do {
      return try await attemptCopy(
        excluding: copySentinel(),
        timings: timings,
        deadline: deadline,
        updateOwnedClipboardChangeCount: updateOwnedClipboardChangeCount
      )
    } catch {
      if shouldRetryCopy(error) {
        try Task.checkCancellation()
        return try await attemptCopy(
          excluding: copySentinel(),
          timings: timings,
          deadline: deadline,
          updateOwnedClipboardChangeCount: updateOwnedClipboardChangeCount
        )
      }
      throw error
    }
  }

  private func attemptCopy(
    excluding sentinel: String,
    timings: Timings,
    deadline: ContinuousClock.Instant,
    updateOwnedClipboardChangeCount: @escaping (Int) -> Void
  ) async throws -> String {
    pasteboard.setString(sentinel)
    updateOwnedClipboardChangeCount(pasteboard.changeCount)
    try await sleepRespectingDeadline(timings.copySettleDelay, until: deadline)

    let remaining = try remainingDuration(until: deadline)
    let minimumReliableCopyWindow = minDuration(.milliseconds(90), timings.copyTimeout)
    guard remaining >= minimumReliableCopyWindow else {
      throw OperationError.timedOut(operationTimeout)
    }

    let beforeCopyChangeCount = pasteboard.changeCount
    keyboard.sendCommandC()
    let waitTimeout = minDuration(timings.copyTimeout, remaining)
    let copiedText = try await pasteboard.waitForCopiedString(
      after: beforeCopyChangeCount,
      excluding: sentinel,
      timeout: waitTimeout
    )
    updateOwnedClipboardChangeCount(pasteboard.changeCount)
    return copiedText
  }

  private func shouldRetryCopy(_ error: Error) -> Bool {
    if error is CancellationError {
      return false
    }
    if let pasteboardError = error as? PasteboardController.PasteboardError {
      switch pasteboardError {
      case .noChange, .noString:
        return true
      }
    }
    return false
  }

  private func copySentinel() -> String {
    "GC_COPY_SENTINEL_" + UUID().uuidString
  }

  private func runCorrector(
    _ corrector: GrammarCorrector,
    text: String,
    deadline: ContinuousClock.Instant
  ) async throws -> String {
    let remaining = try remainingDuration(until: deadline)
    let timeoutError = OperationError.timedOut(operationTimeout)
    let task = Task.detached(priority: .userInitiated) {
      try await corrector.correct(text)
    }
    defer {
      task.cancel()
    }
    return try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
          try await task.value
        }
        group.addTask {
          try await Task.sleep(for: remaining)
          throw timeoutError
        }

        guard let output = try await group.next() else {
          throw timeoutError
        }
        group.cancelAll()
        return output
      }
    } onCancel: {
      task.cancel()
    }
  }

  private func remainingDuration(until deadline: ContinuousClock.Instant) throws -> Duration {
    let remaining = deadline - ContinuousClock.now
    guard remaining > .zero else {
      throw OperationError.timedOut(operationTimeout)
    }
    return remaining
  }

  private func minDuration(_ lhs: Duration, _ rhs: Duration) -> Duration {
    lhs < rhs ? lhs : rhs
  }

  private func sleepRespectingDeadline(_ delay: Duration, until deadline: ContinuousClock.Instant) async throws {
    let remaining = try remainingDuration(until: deadline)
    let boundedDelay = minDuration(delay, remaining)
    try await Task.sleep(for: boundedDelay)
    _ = try remainingDuration(until: deadline)
  }

  private static func defaultAddGlobalKeyMonitor(
    handler: @escaping (UInt16, NSEvent.ModifierFlags) -> Void
  ) -> Any? {
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      handler(event.keyCode, event.modifierFlags)
    }
  }

  private static func defaultAddLocalKeyMonitor(
    handler: @escaping (UInt16, NSEvent.ModifierFlags) -> Bool
  ) -> Any? {
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if handler(event.keyCode, event.modifierFlags) {
        return nil
      }
      return event
    }
  }

  private static func defaultRemoveEventMonitor(_ monitor: Any) {
    NSEvent.removeMonitor(monitor)
  }

  private func createFallbackCorrector() -> GrammarCorrector? {
    if let fallbackCorrectorFactory {
      return fallbackCorrectorFactory()
    }

    let fallbackProvider: Settings.Provider
    switch settings.provider {
    case .gemini:
      fallbackProvider = .openRouter
    case .openRouter:
      fallbackProvider = .gemini
    case .openAI:
      fallbackProvider = .anthropic
    case .anthropic:
      fallbackProvider = .openAI
    }

    let fallbackSettings = Settings(
      provider: fallbackProvider,
      requestTimeoutSeconds: settings.requestTimeoutSeconds,
      activationDelayMilliseconds: settings.activationDelayMilliseconds,
      selectAllDelayMilliseconds: settings.selectAllDelayMilliseconds,
      copySettleDelayMilliseconds: settings.copySettleDelayMilliseconds,
      copyTimeoutMilliseconds: settings.copyTimeoutMilliseconds,
      pasteSettleDelayMilliseconds: settings.pasteSettleDelayMilliseconds,
      postPasteDelayMilliseconds: settings.postPasteDelayMilliseconds,
      timingProfiles: settings.timingProfiles,
      correctionLanguage: settings.correctionLanguage,
      hotKeyCorrectSelection: settings.hotKeyCorrectSelection,
      hotKeyCorrectAll: settings.hotKeyCorrectAll,
      hotKeyAnalyzeTone: settings.hotKeyAnalyzeTone,
      enableGeminiOpenRouterFallback: settings.enableGeminiOpenRouterFallback,
      geminiApiKey: settings.geminiApiKey,
      geminiModel: settings.geminiModel,
      geminiBaseURL: settings.geminiBaseURL,
      geminiMaxAttempts: settings.geminiMaxAttempts,
      geminiMinSimilarity: settings.geminiMinSimilarity,
      geminiExtraInstruction: settings.geminiExtraInstruction,
      openRouterApiKey: settings.openRouterApiKey,
      openRouterModel: settings.openRouterModel,
      openRouterBaseURL: settings.openRouterBaseURL,
      openRouterMaxAttempts: settings.openRouterMaxAttempts,
      openRouterMinSimilarity: settings.openRouterMinSimilarity,
      openRouterExtraInstruction: settings.openRouterExtraInstruction,
      openAIApiKey: settings.openAIApiKey,
      openAIModel: settings.openAIModel,
      openAIBaseURL: settings.openAIBaseURL,
      openAIMaxAttempts: settings.openAIMaxAttempts,
      openAIMinSimilarity: settings.openAIMinSimilarity,
      openAIExtraInstruction: settings.openAIExtraInstruction,
      anthropicApiKey: settings.anthropicApiKey,
      anthropicModel: settings.anthropicModel,
      anthropicBaseURL: settings.anthropicBaseURL,
      anthropicMaxAttempts: settings.anthropicMaxAttempts,
      anthropicMinSimilarity: settings.anthropicMinSimilarity,
      anthropicExtraInstruction: settings.anthropicExtraInstruction
    )

    return CorrectorFactory.make(settings: fallbackSettings)
  }

  private func modelName(for provider: Settings.Provider) -> String {
    switch provider {
    case .gemini:
      return settings.geminiModel
    case .openRouter:
      return settings.openRouterModel
    case .openAI:
      return settings.openAIModel
    case .anthropic:
      return settings.anthropicModel
    }
  }

  private func updateProviderModel(
    for corrector: GrammarCorrector,
    provider: inout Settings.Provider,
    model: inout String
  ) {
    if let reporting = corrector as? DiagnosticsProviderReporting {
      provider = reporting.diagnosticsProvider
      model = reporting.diagnosticsModel
    }
  }
}
