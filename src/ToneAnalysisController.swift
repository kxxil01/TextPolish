import AppKit

@MainActor
final class ToneAnalysisController {
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
    keyboard: KeyboardControlling? = nil,
    pasteboard: PasteboardControlling? = nil,
    onSuccess: (() -> Void)? = nil
  ) {
    self.analyzer = analyzer
    self.feedback = feedback
    self.resultPresenter = resultPresenter
    self.timings = timings
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
      defer {
        self.isRunning = false
        self.currentTask = nil
      }

      guard self.keyboard.isAccessibilityTrusted(prompt: true) else {
        self.feedback.showError("Enable Accessibility")
        return
      }

      let currentPid = ProcessInfo.processInfo.processIdentifier
      let appToActivate: NSRunningApplication? = {
        if let targetApplication, targetApplication.processIdentifier != currentPid { return targetApplication }
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != currentPid { return frontmost }
        return nil
      }()
      if let appToActivate {
        _ = appToActivate.activate(options: [])
        try? await Task.sleep(for: timings.activationDelay)
      }

      let snapshot = self.pasteboard.snapshot()
      defer { self.pasteboard.restore(snapshot) }

      do {
        let inputText = try await self.copySelectedText(timings: timings)
        try Task.checkCancellation()

        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          self.feedback.showError("No text selected")
          return
        }

        self.feedback.showInfo("Analyzing tone...")

        let result = try await self.runAnalyzer(analyzer, text: inputText)
        try Task.checkCancellation()

        self.resultPresenter.showResult(result)
        self.onSuccess?()
      } catch is CancellationError {
        self.feedback.showInfo("Canceled")
      } catch {
        let message =
          (error as? LocalizedError)?.errorDescription ??
          (error as NSError).localizedDescription
        self.resultPresenter.showError(message)
        NSLog("[TextPolish] Tone analysis error: \(error)")
      }
    }
    currentTask = task
  }

  private func maybeShowBusyFeedback() {
    if busyFeedbackGate.shouldShow(now: ContinuousClock.now) {
      feedback.showInfo("Analysis in progress")
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
    try Task.checkCancellation()

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

  private func runAnalyzer(_ analyzer: ToneAnalyzer, text: String) async throws -> ToneAnalysisResult {
    let task = Task.detached(priority: .userInitiated) {
      try await analyzer.analyze(text)
    }
    currentAnalyzerTask = task
    defer {
      currentAnalyzerTask = nil
    }
    return try await withTaskCancellationHandler {
      let result = try await task.value
      // Check for cancellation before returning result
      try Task.checkCancellation()
      return result
    } onCancel: {
      task.cancel()
    }
  }
}
