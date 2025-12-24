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

    private static func duration(milliseconds value: Int) -> Duration {
      .milliseconds(Int64(max(0, value)))
    }
  }

  private var corrector: GrammarCorrector
  private let feedback: FeedbackPresenter
  private let keyboard: KeyboardControlling
  private let pasteboard: PasteboardControlling
  private let recoverer: (@MainActor (Error) async -> String?)?

  private var timings: Timings
  private var isRunning = false
  private var busyFeedbackGate = FeedbackCooldown(cooldown: .milliseconds(900))

  init(
    corrector: GrammarCorrector,
    feedback: FeedbackPresenter,
    timings: Timings = .default,
    keyboard: KeyboardControlling? = nil,
    pasteboard: PasteboardControlling? = nil,
    recoverer: (@MainActor (Error) async -> String?)? = nil
  ) {
    self.corrector = corrector
    self.feedback = feedback
    self.timings = timings
    self.keyboard = keyboard ?? KeyboardController()
    self.pasteboard = pasteboard ?? PasteboardController()
    self.recoverer = recoverer
  }

  func updateCorrector(_ corrector: GrammarCorrector) {
    self.corrector = corrector
  }

  func updateTimings(_ timings: Timings) {
    self.timings = timings
  }

  func correctSelection(targetApplication: NSRunningApplication? = nil) {
    run(mode: .selection, targetApplication: targetApplication)
  }

  func correctAll(targetApplication: NSRunningApplication? = nil) {
    run(mode: .all, targetApplication: targetApplication)
  }

  private enum Mode {
    case selection
    case all
  }

  private func run(mode: Mode, targetApplication: NSRunningApplication?) {
    guard !isRunning else {
      maybeShowBusyFeedback()
      return
    }
    isRunning = true
    let corrector = corrector
    let timings = timings

    Task { @MainActor in
      defer { isRunning = false }

      guard keyboard.isAccessibilityTrusted(prompt: true) else {
        feedback.showError("Enable Accessibility")
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

      let snapshot = pasteboard.snapshot()
      defer { pasteboard.restore(snapshot) }

      do {
        if mode == .all {
          keyboard.sendCommandA()
          try await Task.sleep(for: timings.selectAllDelay)
        }

        let sentinel = "GC_COPY_SENTINEL_" + UUID().uuidString
        pasteboard.setString(sentinel)
        try await Task.sleep(for: timings.copySettleDelay)

        let beforeCopyChangeCount = pasteboard.changeCount
        keyboard.sendCommandC()
        let inputText = try await pasteboard.waitForCopiedString(
          after: beforeCopyChangeCount,
          excluding: sentinel,
          timeout: timings.copyTimeout
        )

        let corrected: String
        do {
          corrected = try await runCorrector(corrector, text: inputText)
        } catch {
          if let recoverer, let message = await recoverer(error) {
            feedback.showInfo(message)
            let retryCorrector = self.corrector
            corrected = try await runCorrector(retryCorrector, text: inputText)
          } else {
            throw error
          }
        }
        guard corrected != inputText else {
          feedback.showInfo("No changes")
          return
        }

        pasteboard.setString(corrected)
        try await Task.sleep(for: timings.pasteSettleDelay)
        keyboard.sendCommandV()
        try await Task.sleep(for: timings.postPasteDelay)
        feedback.showSuccess()
      } catch {
        let message =
          (error as? LocalizedError)?.errorDescription ??
          (error as NSError).localizedDescription
        feedback.showError(message)
        NSLog("[TextPolish] \(error)")
      }
    }
  }

  private func maybeShowBusyFeedback() {
    if busyFeedbackGate.shouldShow(now: ContinuousClock.now) {
      feedback.showInfo("Correction in progress")
    }
  }

  private func runCorrector(_ corrector: GrammarCorrector, text: String) async throws -> String {
    try await Task.detached(priority: .userInitiated) {
      try await corrector.correct(text)
    }.value
  }
}
