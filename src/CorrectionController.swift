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
  private let recoverer: (@MainActor (Error) async -> RecoveryAction?)?
  private let onSuccess: (@MainActor () -> Void)?

  private var timings: Timings
  private var isRunning = false
  private var currentTask: Task<Void, Never>?
  private var busyFeedbackGate = FeedbackCooldown(cooldown: .milliseconds(900))

  init(
    corrector: GrammarCorrector,
    feedback: FeedbackPresenter,
    timings: Timings = .default,
    keyboard: KeyboardControlling? = nil,
    pasteboard: PasteboardControlling? = nil,
    recoverer: (@MainActor (Error) async -> RecoveryAction?)? = nil,
    onSuccess: (@MainActor () -> Void)? = nil
  ) {
    self.corrector = corrector
    self.feedback = feedback
    self.timings = timings
    self.keyboard = keyboard ?? KeyboardController()
    self.pasteboard = pasteboard ?? PasteboardController()
    self.recoverer = recoverer
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

      var didPaste = false

      do {
        if mode == .all {
          self.keyboard.sendCommandA()
          try await Task.sleep(for: timings.selectAllDelay)
        }

        let inputText = try await self.copySelectedText(timings: timings)
        try Task.checkCancellation()

        let corrected: String
        do {
          corrected = try await self.runCorrector(corrector, text: inputText)
        } catch {
          if let recoverer, let action = await recoverer(error) {
            self.feedback.showInfo(action.message)
            let retryCorrector = action.corrector ?? self.corrector
            corrected = try await self.runCorrector(retryCorrector, text: inputText)
          } else {
            throw error
          }
        }
        guard corrected != inputText else {
          self.feedback.showInfo("No changes")
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
        self.onSuccess?()
      } catch is CancellationError {
        if didPaste {
          self.feedback.showSuccess()
          self.onSuccess?()
        } else {
          self.feedback.showInfo("Canceled")
        }
      } catch {
        let message =
          (error as? LocalizedError)?.errorDescription ??
          (error as NSError).localizedDescription
        self.feedback.showError(message)
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
}
