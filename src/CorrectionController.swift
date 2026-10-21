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
  /// Gets what was replaced after a Polish that changed something, for Learn mode and Undo.
  private let onPolished: (@MainActor (PolishRecord) -> Void)?

  private var timings: Timings
  private var operationTimeout: Duration
  private var isRunning = false
  private var currentTask: Task<Void, Never>?
  private var busyFeedbackGate = FeedbackCooldown(cooldown: .milliseconds(900))
  private nonisolated(unsafe) var globalEscapeMonitor: Any?
  private nonisolated(unsafe) var localEscapeMonitor: Any?
  private let frontmostApplicationPIDProvider: @MainActor () -> pid_t?
  private let applicationResolver: @MainActor (pid_t) -> NSRunningApplication?
  private let applicationActivator: @MainActor (NSRunningApplication) -> Void
  private let selectionStateProvider: @MainActor (pid_t?) -> SelectionState
  private let reviewer: PolishReviewing?

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
    applicationActivator: (@MainActor (NSRunningApplication) -> Void)? = nil,
    selectionStateProvider: (@MainActor (pid_t?) -> SelectionState)? = nil,
    reviewer: PolishReviewing? = nil,
    addGlobalKeyMonitor: GlobalKeyMonitorInstaller? = nil,
    addLocalKeyMonitor: LocalKeyMonitorInstaller? = nil,
    removeEventMonitor: EventMonitorRemover? = nil,
    onSuccess: (@MainActor () -> Void)? = nil,
    onPolished: (@MainActor (PolishRecord) -> Void)? = nil
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
    self.applicationActivator = applicationActivator ?? { _ = $0.activate(options: []) }
    // Unknown by default so tests never depend on whichever app is focused; the app injects SelectionProbe.
    self.selectionStateProvider = selectionStateProvider ?? { _ in .unknown }
    self.reviewer = reviewer
    self.addGlobalKeyMonitor = addGlobalKeyMonitor ?? CorrectionController.defaultAddGlobalKeyMonitor
    self.addLocalKeyMonitor = addLocalKeyMonitor ?? CorrectionController.defaultAddLocalKeyMonitor
    self.removeEventMonitor = removeEventMonitor ?? CorrectionController.defaultRemoveEventMonitor
    self.onSuccess = onSuccess
    self.onPolished = onPolished
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

  /// Polishes the selection, or the whole field when nothing is selected.
  /// `text` is the selection when the caller already has it, as a Services request does; nothing is copied then.
  func polish(
    style: CorrectionStyle,
    targetApplication: NSRunningApplication? = nil,
    timingsOverride: Timings? = nil,
    text: String? = nil
  ) {
    run(style: style, targetApplication: targetApplication, timingsOverride: timingsOverride, providedText: text)
  }

  private func run(
    style: CorrectionStyle,
    targetApplication: NSRunningApplication?,
    timingsOverride: Timings?,
    providedText: String?
  ) {
    guard !isRunning else {
      maybeShowBusyFeedback()
      return
    }
    isRunning = true
    let corrector = corrector
    let timings = timingsOverride ?? timings
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      let state = PolishRunState(
        corrector: corrector,
        provider: self.settings.provider,
        model: self.modelName(for: self.settings.provider),
        deadline: ContinuousClock.now + self.operationTimeout
      )
      self.updateProviderModel(for: corrector, provider: &state.provider, model: &state.model)
      defer {
        self.isRunning = false
        self.currentTask = nil
      }

      guard self.keyboard.isAccessibilityTrusted(prompt: true) else {
        self.feedback.showError("Enable Accessibility")
        self.recordFailure(state, message: "Accessibility permission required", measuresLatency: false, retryCount: 0)
        return
      }

      self.installEscapeCancellationMonitors()
      defer {
        self.removeEscapeCancellationMonitorsIfNeeded()
      }

      var didPaste = false
      do {
        let target = self.resolveTarget(targetApplication)
        if let app = target.app, !app.isActive {
          _ = app.activate(options: [])
          try await self.sleepRespectingDeadline(timings.activationDelay, until: state.deadline)
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

        let input: CopiedInput
        if let providedText {
          input = CopiedInput(text: providedText, selection: .selected, wholeField: false)
        } else {
          input = try await self.copyInput(targetPID: target.pid, timings: timings, deadline: state.deadline) {
            ownedClipboardChangeCount = $0
          }
        }
        try Task.checkCancellation()
        guard !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          self.feedback.showError("No text selected")
          self.recordFailure(state, message: "No text selected", retryCount: 0)
          return
        }
        TPLogger.log(
          "Polish input: app=\(target.app?.bundleIdentifier ?? "unknown") style=\(style) "
            + "selection=\(input.selection) wholeField=\(input.wholeField) chars=\(input.text.count)"
        )

        let corrected = try await self.correctWithRecovery(input.text, style: style, corrector: corrector, state: state)
        guard corrected != input.text else {
          self.feedback.showInfo("No changes")
          self.recordSuccess(state, note: "No changes")
          return
        }
        guard let chosen = try await self.confirmInPreviewIfNeeded(
          original: input.text, polished: corrected, style: style, state: state
        ) else {
          return
        }

        let newlinesIn = input.text.filter(\.isNewline).count
        let newlinesOut = chosen.text.filter(\.isNewline).count
        TPLogger.log("Polish output: chars=\(chosen.text.count) newlines=\(newlinesIn)->\(newlinesOut), pasting")
        try Task.checkCancellation()
        try await self.paste(chosen.text, into: target.pid, timings: timings, deadline: state.deadline) {
          ownedClipboardChangeCount = $0
        }
        didPaste = true
        try await self.sleepRespectingDeadline(timings.postPasteDelay, until: state.deadline)
        self.showSuccess(for: chosen.style)
        self.recordSuccess(state)
        self.onSuccess?()
        self.onPolished?(PolishRecord(original: input.text, polished: chosen.text, processID: target.pid, style: chosen.style))
      } catch is CancellationError {
        self.finishCanceled(didPaste: didPaste, style: style, state: state)
      } catch {
        self.finishFailed(error, didPaste: didPaste, style: style, state: state)
      }
    }
    currentTask = task
  }
}

// MARK: - Copy, correct, and timing helpers

extension CorrectionController {
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

  private func showSuccess(for style: CorrectionStyle) {
    if style.rewritesWording {
      feedback.showRewriteSuccess()
    } else {
      feedback.showSuccess()
    }
  }

  private func runCorrector(
    _ corrector: GrammarCorrector,
    text: String,
    style: CorrectionStyle,
    deadline: ContinuousClock.Instant
  ) async throws -> String {
    let remaining = try remainingDuration(until: deadline)
    let timeoutError = OperationError.timedOut(operationTimeout)
    let task = Task.detached(priority: .userInitiated) {
      try await corrector.correct(text, style: style)
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
    case .custom:
      // The Custom provider has no partner to fall back to.
      return nil
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
      polishStyle: settings.polishStyle,
      hotKeyPolish: settings.hotKeyPolish,
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
    case .custom:
      return settings.customProvider.model
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

// MARK: - Polish steps

/// What one Polish has used so far, for Diagnostics and the operation deadline.
@MainActor
private final class PolishRunState {
  var startedAt = Date()
  var deadline: ContinuousClock.Instant
  var provider: Settings.Provider
  var model: String
  var fallbackCount = 0
  var usedCorrector: GrammarCorrector

  init(corrector: GrammarCorrector, provider: Settings.Provider, model: String, deadline: ContinuousClock.Instant) {
    usedCorrector = corrector
    self.provider = provider
    self.model = model
    self.deadline = deadline
  }

  var retryCount: Int {
    (usedCorrector as? RetryReporting)?.lastRetryCount ?? 0
  }

  var latency: Double {
    Date().timeIntervalSince(startedAt)
  }
}

private struct CopiedInput {
  let text: String
  let selection: SelectionState
  let wholeField: Bool
}

extension CorrectionController {
  /// The app to paste back into: the one Polish was started for, else whatever is frontmost, never TextPolish.
  private func resolveTarget(_ targetApplication: NSRunningApplication?) -> (pid: pid_t?, app: NSRunningApplication?) {
    let currentPid = ProcessInfo.processInfo.processIdentifier
    if let targetApplication, targetApplication.processIdentifier != currentPid {
      return (targetApplication.processIdentifier, targetApplication)
    }
    guard let frontmostPID = frontmostApplicationPIDProvider(), frontmostPID != currentPid else {
      return (nil, nil)
    }
    return (frontmostPID, applicationResolver(frontmostPID))
  }

  /// Copies the selection, or the whole field when nothing is selected or nothing could be copied.
  private func copyInput(
    targetPID: pid_t?,
    timings: Timings,
    deadline: ContinuousClock.Instant,
    updateOwnedClipboardChangeCount: @escaping (Int) -> Void
  ) async throws -> CopiedInput {
    let selection = selectionStateProvider(targetPID)
    if selection == .nothingSelected {
      keyboard.sendCommandA()
      try await sleepRespectingDeadline(timings.selectAllDelay, until: deadline)
    }
    do {
      let text = try await copySelectedText(
        timings: timings,
        deadline: deadline,
        updateOwnedClipboardChangeCount: updateOwnedClipboardChangeCount
      )
      return CopiedInput(text: text, selection: selection, wholeField: selection == .nothingSelected)
    } catch where selection == .unknown && shouldRetryCopy(error) {
      // Nothing could be copied and Accessibility could not tell why, so polish the whole field.
      keyboard.sendCommandA()
      try await sleepRespectingDeadline(timings.selectAllDelay, until: deadline)
      let text = try await attemptCopy(
        excluding: copySentinel(),
        timings: timings,
        deadline: deadline,
        updateOwnedClipboardChangeCount: updateOwnedClipboardChangeCount
      )
      return CopiedInput(text: text, selection: selection, wholeField: true)
    }
  }

  /// Runs the corrector, then the fallback provider, then the recoverer, until one produces text.
  private func correctWithRecovery(
    _ text: String,
    style: CorrectionStyle,
    corrector: GrammarCorrector,
    state: PolishRunState
  ) async throws -> String {
    do {
      return try await runCorrector(corrector, text: text, style: style, deadline: state.deadline)
    } catch {
      var unresolvedError = error
      if shouldAttemptFallback?(error) == true, let fallbackCorrector = createFallbackCorrector() {
        feedback.showInfo("Primary provider failed, trying fallback provider...")
        state.fallbackCount += 1
        state.usedCorrector = fallbackCorrector
        updateProviderModel(for: fallbackCorrector, provider: &state.provider, model: &state.model)
        do {
          return try await runCorrector(fallbackCorrector, text: text, style: style, deadline: state.deadline)
        } catch {
          unresolvedError = error
        }
      }
      guard let recoverer, let action = await recoverer(unresolvedError) else {
        throw unresolvedError
      }
      feedback.showInfo(action.message)
      let retryCorrector = action.corrector ?? self.corrector
      state.usedCorrector = retryCorrector
      updateProviderModel(for: retryCorrector, provider: &state.provider, model: &state.model)
      return try await runCorrector(retryCorrector, text: text, style: style, deadline: state.deadline)
    }
  }

  /// With Preview on, waits for Paste or Cancel, polishing the original again when the user asks.
  /// Returns the text and style to paste, or nil when the user canceled.
  private func confirmInPreviewIfNeeded(
    original: String,
    polished: String,
    style: CorrectionStyle,
    state: PolishRunState
  ) async throws -> (text: String, style: CorrectionStyle)? {
    guard settings.previewBeforePaste, let reviewer else { return (polished, style) }
    defer { reviewer.dismiss() }
    var current = (text: polished, style: style)
    while true {
      TPLogger.log("Polish preview: waiting for Paste or Cancel")
      let reviewStartedAt = Date()
      let decision = await reviewer.review(
        original: original, polished: current.text, style: current.style, choices: previewStyleChoices(for: current.style)
      )
      // Diagnostics latency measures Polish, not how long the user read the preview.
      state.startedAt += Date().timeIntervalSince(reviewStartedAt)
      try Task.checkCancellation()
      // Time spent reading the preview does not count against the operation timeout.
      state.deadline = ContinuousClock.now + operationTimeout
      switch decision {
      case .paste:
        return current
      case .cancel:
        feedback.showInfo("Canceled")
        recordNote(state, message: "Canceled in preview")
        return nil
      case .retry(let newStyle):
        TPLogger.log("Polish preview: trying again style=\(newStyle)")
        let text = try await correctWithRecovery(original, style: newStyle, corrector: state.usedCorrector, state: state)
        current = (text, newStyle)
      }
    }
  }

  /// Styles the preview offers for another try; a translation or reply stays one.
  private func previewStyleChoices(for style: CorrectionStyle) -> [PolishStyleChoice] {
    guard !style.translatesToEnglish else { return [] }
    return settings.availablePolishStyles.map {
      PolishStyleChoice(name: settings.displayName(for: $0), style: settings.correctionStyle(for: $0))
    }
  }

  /// Puts the result on the clipboard, returns to the target app, and sends ⌘V.
  private func paste(
    _ text: String,
    into targetPID: pid_t?,
    timings: Timings,
    deadline: ContinuousClock.Instant,
    updateOwnedClipboardChangeCount: (Int) -> Void
  ) async throws {
    pasteboard.setString(text)
    let ownedChangeCount = pasteboard.changeCount
    updateOwnedClipboardChangeCount(ownedChangeCount)
    try await sleepRespectingDeadline(timings.pasteSettleDelay, until: deadline)
    try Task.checkCancellation()
    guard pasteboard.changeCount == ownedChangeCount else {
      throw OperationError.clipboardChanged
    }
    if let targetPID, frontmostApplicationPIDProvider() != targetPID {
      if let appToActivate = applicationResolver(targetPID) {
        applicationActivator(appToActivate)
        // Switching back can take longer than one activation delay, for example after the preview panel.
        for _ in 0..<10 where frontmostApplicationPIDProvider() != targetPID {
          try await sleepRespectingDeadline(timings.activationDelay, until: deadline)
        }
      }
      guard frontmostApplicationPIDProvider() == targetPID else {
        throw OperationError.targetApplicationChanged
      }
    }
    keyboard.sendCommandV()
  }

  private func finishCanceled(didPaste: Bool, style: CorrectionStyle, state: PolishRunState) {
    guard didPaste else {
      feedback.showInfo("Canceled")
      recordNote(state, message: "Canceled")
      return
    }
    showSuccess(for: style)
    recordSuccess(state, note: "Canceled after paste")
    onSuccess?()
  }

  private func finishFailed(_ error: Error, didPaste: Bool, style: CorrectionStyle, state: PolishRunState) {
    if didPaste, let operationError = error as? OperationError, case .timedOut = operationError {
      showSuccess(for: style)
      recordSuccess(state, note: "Timed out after paste")
      onSuccess?()
      return
    }
    let message = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
    feedback.showError(message)
    recordFailure(state, message: message, error: error)
    TPLogger.log("\(error)")
  }

  // MARK: Diagnostics

  private func recordSuccess(_ state: PolishRunState, note: String? = nil) {
    DiagnosticsStore.shared.recordSuccess(
      operation: .correction,
      provider: state.provider,
      model: state.model,
      latencySeconds: state.latency,
      retryCount: state.retryCount,
      fallbackCount: state.fallbackCount,
      note: note
    )
  }

  private func recordNote(_ state: PolishRunState, message: String) {
    DiagnosticsStore.shared.recordNote(
      operation: .correction,
      provider: state.provider,
      model: state.model,
      latencySeconds: state.latency,
      retryCount: state.retryCount,
      fallbackCount: state.fallbackCount,
      message: message,
      updateHealth: false
    )
  }

  private func recordFailure(
    _ state: PolishRunState,
    message: String,
    error: Error? = nil,
    measuresLatency: Bool = true,
    retryCount: Int? = nil
  ) {
    DiagnosticsStore.shared.recordFailure(
      operation: .correction,
      provider: state.provider,
      model: state.model,
      latencySeconds: measuresLatency ? state.latency : nil,
      retryCount: retryCount ?? state.retryCount,
      fallbackCount: state.fallbackCount,
      message: message,
      error: error
    )
  }
}
