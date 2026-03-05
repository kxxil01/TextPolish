import AppKit

@MainActor
final class ToneAnalysisController {
  private enum OperationError: LocalizedError {
    case timedOut(Duration)

    var errorDescription: String? {
      switch self {
      case .timedOut(let timeout):
        let seconds = max(1, Int(timeout.components.seconds))
        return "Tone analysis timed out after \(seconds) seconds"
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
  private var currentAnalyzerTask: Task<ToneAnalysisResult, Error>?
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
    // Also cancel the analyzer task if it's running
    currentAnalyzerTask?.cancel()
    return true
  }

  func analyzeSelection(targetApplication: NSRunningApplication? = nil, timingsOverride: Timings? = nil) {
    guard !isRunning else {
      maybeShowBusyFeedback()
      return
    }
    isRunning = true
    let analyzer = analyzer
    let timings = timingsOverride ?? timings
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      let operationStartedAt = Date()
      let deadline = ContinuousClock.now + self.operationTimeout
      let resolveProviderModel: () -> (Settings.Provider, String) = {
        if let reporting = analyzer as? DiagnosticsProviderReporting {
          return (reporting.diagnosticsProvider, reporting.diagnosticsModel)
        }
        return (.gemini, "Unknown")
      }
      defer {
        self.isRunning = false
        self.currentTask = nil
      }

      guard self.keyboard.isAccessibilityTrusted(prompt: true) else {
        self.feedback.showError("Enable Accessibility")
        let (provider, model) = resolveProviderModel()
        DiagnosticsStore.shared.recordFailure(
          operation: .toneAnalysis,
          provider: provider,
          model: model,
          latencySeconds: nil,
          retryCount: 0,
          fallbackCount: 0,
          message: "Accessibility permission required",
          error: nil
        )
        return
      }

      do {
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let appToActivate: NSRunningApplication? = {
          if let targetApplication, targetApplication.processIdentifier != currentPid { return targetApplication }
          if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != currentPid { return frontmost }
          return nil
        }()
        if let appToActivate, !appToActivate.isActive {
          _ = appToActivate.activate(options: [])
          try await self.sleepRespectingDeadline(timings.activationDelay, until: deadline)
        }

        let snapshot = self.pasteboard.snapshot()
        defer { self.pasteboard.restore(snapshot) }

        let inputText = try await self.copySelectedText(timings: timings, deadline: deadline)
        try Task.checkCancellation()

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          self.feedback.showError("No text selected")
          let (provider, model) = resolveProviderModel()
          DiagnosticsStore.shared.recordFailure(
            operation: .toneAnalysis,
            provider: provider,
            model: model,
            latencySeconds: Date().timeIntervalSince(operationStartedAt),
            retryCount: 0,
            fallbackCount: 0,
            message: "No text selected",
            error: nil
          )
          return
        }

        self.feedback.showInfo("Analyzing tone...")

        let result = try await self.runAnalyzer(analyzer, text: inputText, deadline: deadline)
        try Task.checkCancellation()

        self.resultPresenter.showResult(result)
        let retryCount = (analyzer as? RetryReporting)?.lastRetryCount ?? 0
        let (provider, model) = resolveProviderModel()
        DiagnosticsStore.shared.recordSuccess(
          operation: .toneAnalysis,
          provider: provider,
          model: model,
          latencySeconds: Date().timeIntervalSince(operationStartedAt),
          retryCount: retryCount,
          fallbackCount: 0
        )
        self.onSuccess?()
      } catch is CancellationError {
        self.feedback.showInfo("Canceled")
        let retryCount = (analyzer as? RetryReporting)?.lastRetryCount ?? 0
        let (provider, model) = resolveProviderModel()
        DiagnosticsStore.shared.recordNote(
          operation: .toneAnalysis,
          provider: provider,
          model: model,
          latencySeconds: Date().timeIntervalSince(operationStartedAt),
          retryCount: retryCount,
          fallbackCount: 0,
          message: "Canceled",
          updateHealth: false
        )
      } catch {
        let message =
          (error as? LocalizedError)?.errorDescription ??
          (error as NSError).localizedDescription
        self.resultPresenter.showError(message)
        let retryCount = (analyzer as? RetryReporting)?.lastRetryCount ?? 0
        let (provider, model) = resolveProviderModel()
        DiagnosticsStore.shared.recordFailure(
          operation: .toneAnalysis,
          provider: provider,
          model: model,
          latencySeconds: Date().timeIntervalSince(operationStartedAt),
          retryCount: retryCount,
          fallbackCount: 0,
          message: message,
          error: error
        )
        TPLogger.log("Tone analysis error: \(error)")
      }
    }
    currentTask = task
  }

  private func maybeShowBusyFeedback() {
    if busyFeedbackGate.shouldShow(now: ContinuousClock.now) {
      feedback.showInfo("Analysis in progress")
    }
  }

  private func copySelectedText(timings: Timings, deadline: ContinuousClock.Instant) async throws -> String {
    do {
      return try await attemptCopy(excluding: copySentinel(), timings: timings, deadline: deadline)
    } catch {
      if shouldRetryCopy(error) {
        try Task.checkCancellation()
        return try await attemptCopy(excluding: copySentinel(), timings: timings, deadline: deadline)
      }
      throw error
    }
  }

  private func attemptCopy(
    excluding sentinel: String,
    timings: Timings,
    deadline: ContinuousClock.Instant
  ) async throws -> String {
    pasteboard.setString(sentinel)
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
    return try await pasteboard.waitForCopiedString(
      after: beforeCopyChangeCount,
      excluding: sentinel,
      timeout: waitTimeout
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

  private func runAnalyzer(
    _ analyzer: ToneAnalyzer,
    text: String,
    deadline: ContinuousClock.Instant
  ) async throws -> ToneAnalysisResult {
    let remaining = try remainingDuration(until: deadline)
    let timeoutError = OperationError.timedOut(operationTimeout)
    let task = Task.detached(priority: .userInitiated) {
      try await analyzer.analyze(text)
    }
    currentAnalyzerTask = task
    defer {
      currentAnalyzerTask = nil
      task.cancel()
    }
    return try await withTaskCancellationHandler {
      let result = try await withThrowingTaskGroup(of: ToneAnalysisResult.self) { group in
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
