import AppKit

@MainActor
protocol FeedbackPresenter {
  func showSuccess()
  func showInfo(_ message: String)
  func showError(_ message: String)
}

@MainActor
final class StatusItemFeedback: FeedbackPresenter {
  private let statusItem: NSStatusItem
  private let baseImage: NSImage?

  init(statusItem: NSStatusItem, baseImage: NSImage?) {
    self.statusItem = statusItem
    self.baseImage = baseImage
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
    let previousToolTip = statusItem.button?.toolTip
    let previousTitle = statusItem.button?.title
    statusItem.button?.image = image
    statusItem.button?.title = title ?? ""
    if let toolTip {
      statusItem.button?.toolTip = toolTip
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
      self?.statusItem.button?.image = self?.baseImage
      self?.statusItem.button?.toolTip = previousToolTip
      self?.statusItem.button?.title = previousTitle ?? ""
    }
  }
}
