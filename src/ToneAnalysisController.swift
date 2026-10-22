import AppKit

/// Copies the selection and runs a read-only job on it, restoring the clipboard: Analyze Tone or Explain Message.
@MainActor
final class ToneAnalysisController {
  private enum OperationError: LocalizedError {
    case timedOut(Duration)

    var errorDescription: String? {
      switch self {
      case .timedOut(let timeout):
        let seconds = max(1, Int(timeout.components.seconds))
        return "The request timed out after \(seconds) seconds"
      }
    }
  }

  struct Timings: Sendable {
    let activationDelay: Duration
    let copySettleDelay: Duration
    let copyTimeout: Duration

    static let `default` = Timings(
      activationDelay: .milliseconds(80),
      copySettleDelay: .milliseconds(20),
      copyTimeout: .milliseconds(900)
    )

    init(
      activationDelay: Duration,
      copySettleDelay: Duration,
      copyTimeout: Duration
    ) {
      self.activationDelay = activationDelay
      self.copySettleDelay = copySettleDelay
      self.copyTimeout = copyTimeout
    }

    init(settings: Settings) {
      activationDelay = .milliseconds(Int64(max(0, settings.activationDelayMilliseconds)))
      copySettleDelay = .milliseconds(Int64(max(0, settings.copySettleDelayMilliseconds)))
      copyTimeout = .milliseconds(Int64(max(0, settings.copyTimeoutMilliseconds)))
    }
  }

  private var analyzer: ToneAnalyzer
  private let feedback: FeedbackPresenter
  private let resultPresenter: ToneAnalysisResultPresenter
  private let keyboard: KeyboardControlling
  private let pasteboard: PasteboardControlling

  private var timings: Timings
  private var operationTimeout: Duration
  private var isRunning = false
  private var currentTask: Task<Void, Never>?
  private var cancelCurrentWork: (() -> Void)?
  private var busyFeedbackGate = FeedbackCooldown(cooldown: .milliseconds(900))
  private let onSuccess: (() -> Void)?

  init(
    analyzer: ToneAnalyzer,
    feedback: FeedbackPresenter,
    resultPresenter: ToneAnalysisResultPresenter,
    timings: Timings = .default,
    operationTimeout: Duration = .seconds(8),
    keyboard: KeyboardControlling? = nil,
    pasteboard: PasteboardControlling? = nil,
    onSuccess: (() -> Void)? = nil
  ) {
    self.analyzer = analyzer
    self.feedback = feedback
    self.resultPresenter = resultPresenter
    self.timings = timings
    self.operationTimeout = operationTimeout
    self.keyboard = keyboard ?? KeyboardController()
    self.pasteboard = pasteboard ?? PasteboardController()
    self.onSuccess = onSuccess
  }

  func updateAnalyzer(_ analyzer: ToneAnalyzer) {
    // Cancel any ongoing analysis to prevent race conditions
    cancelCurrentAnalysis()
    self.analyzer = analyzer
  }

  func updateTimings(_ timings: Timings) {
    self.timings = timings
  }

  func updateOperationTimeout(_ timeout: Duration) {
    self.operationTimeout = timeout
  }

  var isBusy: Bool {
    isRunning
  }

  @discardableResult
  func cancelCurrentAnalysis() -> Bool {
    guard isRunning, let currentTask else { return false }
    currentTask.cancel()
    // Also cancel the provider request if it's running
    cancelCurrentWork?()
    return true
  }

  func analyzeSelection(targetApplication: NSRunningApplication? = nil, timingsOverride: Timings? = nil) {
    let analyzer = analyzer
    let job = SelectionJob(
      operation: .toneAnalysis,
      progressMessage: "Analyzing tone...",
      reporting: analyzer as? DiagnosticsProviderReporting,
      retryReporting: analyzer as? RetryReporting,
      perform: { [weak self] text, deadline in
        guard let self else { return }
        let result = try await self.runWithDeadline(deadline) { try await analyzer.analyze(text) }
        self.resultPresenter.showResult(result)
      },
      showError: { [weak self] message in
        self?.resultPresenter.showError(message)
      }
    )
    run(job, targetApplication: targetApplication, timingsOverride: timingsOverride)
  }

  /// Explain Message: copies the selection and shows what it means. `onExplained` gets the message, for Reply.
  /// `text` is the selection when the caller already has it, as a Services request does; nothing is copied then.
  func explainSelection(
    explainer: MessageExplaining,
    language: Settings.ExplanationLanguage,
    presenter: MessageExplanationPresenting,
    targetApplication: NSRunningApplication? = nil,
    timingsOverride: Timings? = nil,
    text: String? = nil,
    onExplained: (@MainActor (String) -> Void)? = nil
  ) {
    let job = SelectionJob(
      operation: .messageExplanation,
      progressMessage: "Explaining...",
      reporting: explainer as? DiagnosticsProviderReporting,
      retryReporting: explainer as? RetryReporting,
      perform: { [weak self] text, deadline in
        guard let self else { return }
        presenter.showLoading()
        let explanation = try await self.runWithDeadline(deadline) { try await explainer.explainMessage(text, in: language) }
        presenter.show(explanation: explanation)
        TPLogger.log("Explain: chars=\(text.count) phrases=\(explanation.phrases.count)")
        onExplained?(text)
      },
      showError: { message in
        presenter.showError(message)
      }
    )
    run(job, targetApplication: targetApplication, timingsOverride: timingsOverride, providedText: text)
  }

  /// One read-only use of the selection: Analyze Tone or Explain Message.
  private struct SelectionJob {
    let operation: DiagnosticsOperation
    let progressMessage: String
    let reporting: DiagnosticsProviderReporting?
    let retryReporting: RetryReporting?
    let perform: @MainActor (String, ContinuousClock.Instant) async throws -> Void
    let showError: @MainActor (String) -> Void

    var providerModel: (Settings.Provider, String) {
      reporting.map { ($0.diagnosticsProvider, $0.diagnosticsModel) } ?? (.gemini, "Unknown")
    }

    var retryCount: Int {
      retryReporting?.lastRetryCount ?? 0
    }
  }

  /// Copies the selection, runs the job on it, and restores the clipboard, recording the outcome for Diagnostics.
  private func run(
    _ job: SelectionJob,
    targetApplication: NSRunningApplication?,
    timingsOverride: Timings?,
    providedText: String? = nil
  ) {
    guard !isRunning else {
      maybeShowBusyFeedback()
      return
    }
    isRunning = true
    let timings = timingsOverride ?? timings
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      let startedAt = Date()
      let deadline = ContinuousClock.now + self.operationTimeout
      defer {
        self.isRunning = false
        self.currentTask = nil
      }

      guard self.keyboard.isAccessibilityTrusted(prompt: true) else {
        self.feedback.showError("Enable Accessibility")
        self.recordFailure(job, message: "Accessibility permission required", latency: nil, error: nil)
        return
      }

      do {
        // Handed-over text needs no copy, so the clipboard is never touched.
        if providedText == nil {
          try await self.activate(targetApplication, timings: timings, deadline: deadline)
        }
        let snapshot = providedText == nil ? self.pasteboard.snapshot() : nil
        var ownedClipboardChangeCount: Int?
        defer {
          if let snapshot, let ownedClipboardChangeCount,
             self.pasteboard.changeCount == ownedClipboardChangeCount
          {
            self.pasteboard.restore(snapshot)
          }
        }

        let inputText: String
        if let providedText {
          inputText = providedText
        } else {
          inputText = try await self.copySelectedText(
            timings: timings,
            deadline: deadline,
            updateOwnedClipboardChangeCount: { ownedClipboardChangeCount = $0 }
          )
        }
        try Task.checkCancellation()

        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          self.feedback.showError("No text selected")
          self.recordFailure(job, message: "No text selected", latency: Date().timeIntervalSince(startedAt), error: nil)
          return
        }

        self.feedback.showInfo(job.progressMessage)
        try await job.perform(inputText, deadline)
        try Task.checkCancellation()
        DiagnosticsStore.shared.recordSuccess(
          operation: job.operation,
          provider: job.providerModel.0,
          model: job.providerModel.1,
          latencySeconds: Date().timeIntervalSince(startedAt),
          retryCount: job.retryCount,
          fallbackCount: 0
        )
        self.onSuccess?()
      } catch is CancellationError {
        self.feedback.showInfo("Canceled")
        DiagnosticsStore.shared.recordNote(
          operation: job.operation,
          provider: job.providerModel.0,
          model: job.providerModel.1,
          latencySeconds: Date().timeIntervalSince(startedAt),
          retryCount: job.retryCount,
          fallbackCount: 0,
          message: "Canceled",
          updateHealth: false
        )
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? (error as NSError).localizedDescription
        job.showError(message)
        self.recordFailure(job, message: message, latency: Date().timeIntervalSince(startedAt), error: error)
        TPLogger.log("\(job.operation.rawValue) error: \(error)")
      }
    }
    currentTask = task
  }

  /// Brings back the app the selection is in, never TextPolish itself.
  private func activate(_ targetApplication: NSRunningApplication?, timings: Timings, deadline: ContinuousClock.Instant) async throws {
    let currentPid = ProcessInfo.processInfo.processIdentifier
    let appToActivate: NSRunningApplication? = {
      if let targetApplication, targetApplication.processIdentifier != currentPid { return targetApplication }
      if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != currentPid { return frontmost }
      return nil
    }()
    if let appToActivate, !appToActivate.isActive {
      _ = appToActivate.activate(options: [])
      try await sleepRespectingDeadline(timings.activationDelay, until: deadline)
    }
  }

  private func recordFailure(_ job: SelectionJob, message: String, latency: Double?, error: Error?) {
    DiagnosticsStore.shared.recordFailure(
      operation: job.operation,
      provider: job.providerModel.0,
      model: job.providerModel.1,
      latencySeconds: latency,
      retryCount: job.retryCount,
      fallbackCount: 0,
      message: message,
      error: error
    )
  }

  private func maybeShowBusyFeedback() {
    if busyFeedbackGate.shouldShow(now: ContinuousClock.now) {
      feedback.showInfo("Analysis in progress")
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
    try Task.checkCancellation()

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

  /// Runs `work` off the main thread and stops waiting at the deadline or when the user cancels.
  private func runWithDeadline<T: Sendable>(
    _ deadline: ContinuousClock.Instant,
    _ work: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    let remaining = try remainingDuration(until: deadline)
    let timeoutError = OperationError.timedOut(operationTimeout)
    let task = Task.detached(priority: .userInitiated) {
      try await work()
    }
    cancelCurrentWork = { task.cancel() }
    defer {
      cancelCurrentWork = nil
      task.cancel()
    }
    return try await withTaskCancellationHandler {
      let result = try await withThrowingTaskGroup(of: T.self) { group in
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
      try Task.checkCancellation()
      return result
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
}

#if DEBUG
extension ToneAnalysisController {
  var debugOperationTimeout: Duration {
    operationTimeout
  }
}
#endif
