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

@MainActor
final class CorrectionController {
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
  private let settings: Settings
  private let recoverer: (@MainActor (Error) async -> RecoveryAction?)?
  private let shouldAttemptFallback: (@MainActor (Error) -> Bool)?
  private let onSuccess: (@MainActor () -> Void)?

  private var timings: Timings
  private var isRunning = false
  private var currentTask: Task<Void, Never>?
  private var busyFeedbackGate = FeedbackCooldown(cooldown: .milliseconds(900))

  init(
    corrector: GrammarCorrector,
    feedback: FeedbackPresenter,
    settings: Settings,
    timings: Timings = .default,
    keyboard: KeyboardControlling? = nil,
    pasteboard: PasteboardControlling? = nil,
    recoverer: (@MainActor (Error) async -> RecoveryAction?)? = nil,
    shouldAttemptFallback: (@MainActor (Error) -> Bool)? = nil,
    onSuccess: (@MainActor () -> Void)? = nil
  ) {
    self.corrector = corrector
    self.feedback = feedback
    self.settings = settings
    self.timings = timings
    self.keyboard = keyboard ?? KeyboardController()
    self.pasteboard = pasteboard ?? PasteboardController()
    self.recoverer = recoverer
    self.shouldAttemptFallback = shouldAttemptFallback
    self.onSuccess = onSuccess
  }

  func updateCorrector(_ corrector: GrammarCorrector) {
    self.corrector = corrector
  }

  func updateTimings(_ timings: Timings) {
    self.timings = timings
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

      let currentPid = ProcessInfo.processInfo.processIdentifier
      let appToActivate: NSRunningApplication? = {
        if let targetApplication, targetApplication.processIdentifier != currentPid { return targetApplication }
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != currentPid { return frontmost }
        return nil
      }()
      if let appToActivate {
        if !appToActivate.isActive {
          _ = appToActivate.activate(options: [])
          try? await Task.sleep(for: timings.activationDelay)
        }
      }

      let snapshot = self.pasteboard.snapshot()
      defer { self.pasteboard.restore(snapshot) }

      var didPaste = false

      do {
        if mode == .all {
          self.keyboard.sendCommandA()
          try await Task.sleep(for: timings.selectAllDelay)
        }

        let inputText = try await self.copySelectedText(timings: timings)
        try Task.checkCancellation()

        var corrected: String
        do {
          corrected = try await self.runCorrector(corrector, text: inputText)
        } catch {
          // Check if we should try fallback provider
          if shouldAttemptFallback?(error) == true,
             let fallbackCorrector = createFallbackCorrector()
          {
            self.feedback.showInfo("Primary provider failed, trying fallback provider...")
            do {
              fallbackCount += 1
              usedCorrector = fallbackCorrector
              self.updateProviderModel(for: fallbackCorrector, provider: &activeProvider, model: &activeModel)
              corrected = try await self.runCorrector(fallbackCorrector, text: inputText)
            } catch {
              // Both failed, show fallback alert
              let fallback = FallbackController(
                fallbackProvider: fallbackCorrector,
                showSuccess: { [weak self] in
                  self?.feedback.showSuccess()
                  self?.onSuccess?()
                },
                showInfo: { [weak self] message in
                  self?.feedback.showInfo(message)
                },
                showError: { [weak self] message in
                  self?.feedback.showError(message)
                }
              )

              fallback.showFallbackAlert(for: error, corrector: corrector, text: inputText)
              throw error
            }
          }

          // Use recoverer if available
          if let recoverer, let action = await recoverer(error) {
            self.feedback.showInfo(action.message)
            let retryCorrector = action.corrector ?? self.corrector
            usedCorrector = retryCorrector
            self.updateProviderModel(for: retryCorrector, provider: &activeProvider, model: &activeModel)
            corrected = try await self.runCorrector(retryCorrector, text: inputText)
          } else {
            throw error
          }
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
        try await Task.sleep(for: timings.pasteSettleDelay)
        try Task.checkCancellation()
        self.keyboard.sendCommandV()
        didPaste = true
        try await Task.sleep(for: timings.postPasteDelay)
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
        NSLog("[TextPolish] \(error)")
      }
    }
    currentTask = task
  }

  private func maybeShowBusyFeedback() {
    if busyFeedbackGate.shouldShow(now: ContinuousClock.now) {
      feedback.showInfo("Correction in progress")
    }
  }

  private func copySelectedText(timings: Timings) async throws -> String {
    do {
      return try await attemptCopy(excluding: copySentinel(), timings: timings)
    } catch {
      if shouldRetryCopy(error) {
        try Task.checkCancellation()
        return try await attemptCopy(excluding: copySentinel(), timings: timings)
      }
      throw error
    }
  }

  private func attemptCopy(excluding sentinel: String, timings: Timings) async throws -> String {
    pasteboard.setString(sentinel)
    try await Task.sleep(for: timings.copySettleDelay)

    let beforeCopyChangeCount = pasteboard.changeCount
    keyboard.sendCommandC()
    return try await pasteboard.waitForCopiedString(
      after: beforeCopyChangeCount,
      excluding: sentinel,
      timeout: timings.copyTimeout
    )
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

  private func runCorrector(_ corrector: GrammarCorrector, text: String) async throws -> String {
    let task = Task.detached(priority: .userInitiated) {
      try await corrector.correct(text)
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  private func createFallbackCorrector() -> GrammarCorrector? {
    let fallbackSettings = Settings(
      provider: settings.provider == .gemini ? .openRouter : .gemini,
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
      fallbackToOpenRouterOnGeminiError: settings.fallbackToOpenRouterOnGeminiError,
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
      openRouterExtraInstruction: settings.openRouterExtraInstruction
    )

    return CorrectorFactory.make(settings: fallbackSettings)
  }

  private func modelName(for provider: Settings.Provider) -> String {
    switch provider {
    case .gemini:
      return settings.geminiModel
    case .openRouter:
      return settings.openRouterModel
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
      return
    }
    if corrector is GeminiCorrector {
      provider = .gemini
      model = modelName(for: .gemini)
    } else if corrector is OpenRouterCorrector {
      provider = .openRouter
      model = modelName(for: .openRouter)
    }
  }
}
