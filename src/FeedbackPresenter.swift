import AppKit

@MainActor
protocol FeedbackPresenter {
  func showSuccess()
  func showInfo(_ message: String)
  func showError(_ message: String)
}

@MainActor
final class StatusItemFeedback: FeedbackPresenter {
  typealias SleepHandler = (Duration) async -> Void

  private let statusItem: NSStatusItem
  private var baseImage: NSImage?
  private let baseToolTip: String?
  private let baseTitle: String?
  private let sleepHandler: SleepHandler
  private var resetTask: Task<Void, Never>?

  init(
    statusItem: NSStatusItem,
    baseImage: NSImage?,
    sleepHandler: @escaping SleepHandler = StatusItemFeedback.defaultSleep
  ) {
    self.statusItem = statusItem
    self.baseImage = baseImage
    self.baseToolTip = statusItem.button?.toolTip
    self.baseTitle = statusItem.button?.title
    self.sleepHandler = sleepHandler
  }

  func updateBaseImage(_ image: NSImage?) {
    self.baseImage = image
  }

  func showSuccess() {
    flash(symbolName: "checkmark.circle", title: "✓", toolTip: "Corrected", seconds: 0.8)
  }

  func showInfo(_ message: String) {
    flash(symbolName: "info.circle", title: "i", toolTip: message, seconds: 0.9)
  }

  func showError(_ message: String) {
    NSSound.beep()
    flash(symbolName: "exclamationmark.triangle", title: "!", toolTip: message, seconds: 1.1)
  }

  private func flash(symbolName: String, title: String?, toolTip: String?, seconds: TimeInterval) {
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    statusItem.button?.image = image
    statusItem.button?.title = title ?? ""
    if let toolTip {
      statusItem.button?.toolTip = toolTip
    }
    resetTask?.cancel()
    resetTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let delayMilliseconds = Int64(max(0.0, seconds) * 1000.0)
      await self.sleepHandler(.milliseconds(delayMilliseconds))
      guard !Task.isCancelled else { return }
      self.statusItem.button?.image = self.baseImage
      self.statusItem.button?.toolTip = self.baseToolTip
      self.statusItem.button?.title = self.baseTitle ?? ""
    }
  }

  private static func defaultSleep(_ duration: Duration) async {
    try? await Task.sleep(for: duration)
  }
}
