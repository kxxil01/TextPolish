import AppKit

@MainActor
final class CorrectionController {
  private var corrector: GrammarCorrector
  private let feedback: FeedbackPresenter
  private let keyboard = KeyboardController()
  private let pasteboard = PasteboardController()
  private let recoverer: (@MainActor (Error) async -> String?)?

  private var isRunning = false

  init(
    corrector: GrammarCorrector,
    feedback: FeedbackPresenter,
    recoverer: (@MainActor (Error) async -> String?)? = nil
  ) {
    self.corrector = corrector
    self.feedback = feedback
    self.recoverer = recoverer
  }

  func updateCorrector(_ corrector: GrammarCorrector) {
    self.corrector = corrector
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
    guard !isRunning else { return }
    isRunning = true
    let corrector = corrector

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
        try? await Task.sleep(for: .milliseconds(80))
      }

      let snapshot = pasteboard.snapshot()
      defer { pasteboard.restore(snapshot) }

      do {
        if mode == .all {
          keyboard.sendCommandA()
          try await Task.sleep(for: .milliseconds(60))
        }

        let sentinel = "GC_COPY_SENTINEL_" + UUID().uuidString
        pasteboard.setString(sentinel)
        try await Task.sleep(for: .milliseconds(20))

        let beforeCopyChangeCount = pasteboard.changeCount
        keyboard.sendCommandC()
        let inputText = try await pasteboard.waitForCopiedString(
          after: beforeCopyChangeCount,
          excluding: sentinel,
          timeout: .milliseconds(900)
        )

        let corrected: String
        do {
          corrected = try await corrector.correct(inputText)
        } catch {
          if let recoverer, let message = await recoverer(error) {
            feedback.showInfo(message)
            let retryCorrector = self.corrector
            corrected = try await retryCorrector.correct(inputText)
          } else {
            throw error
          }
        }
        guard corrected != inputText else {
          feedback.showInfo("No changes")
          return
        }

        pasteboard.setString(corrected)
        try await Task.sleep(for: .milliseconds(25))
        keyboard.sendCommandV()
        try await Task.sleep(for: .milliseconds(180))
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
}
