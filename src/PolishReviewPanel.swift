import AppKit

/// Asks the user to confirm a Polish result before it replaces their text.
@MainActor
protocol PolishReviewing: AnyObject {
  /// Shows what changed and returns true when the user chooses to paste it.
  func review(original: String, polished: String) async -> Bool
}

/// A small panel with the changes highlighted: Return pastes, Escape or closing cancels.
/// It takes keyboard input without activating TextPolish, so the app being polished stays in front.
@MainActor
final class PolishReviewPanel: NSObject, PolishReviewing, NSWindowDelegate {
  private var panel: NSPanel?
  private var continuation: CheckedContinuation<Bool, Never>?

  func review(original: String, polished: String) async -> Bool {
    finish(approved: false)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        self.show(changes: WordDiff.changes(from: original, to: polished))
      }
    } onCancel: {
      Task { @MainActor in self.finish(approved: false) }
    }
  }

  func windowWillClose(_: Notification) {
    finish(approved: false)
  }

  @objc private func paste() {
    finish(approved: true)
  }

  @objc private func cancel() {
    finish(approved: false)
  }

  private func finish(approved: Bool) {
    if let panel {
      panel.delegate = nil
      panel.orderOut(nil)
      self.panel = nil
    }
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(returning: approved)
  }

  private func show(changes: [WordDiff.Change]) {
    let width: CGFloat = 520
    let padding: CGFloat = 16
    let buttonHeight: CGFloat = 32
    let font = NSFont.systemFont(ofSize: 14)
    let text = WordDiff.attributedString(from: changes, font: font)

    let textWidth = width - padding * 2
    let measured = text.boundingRect(
      with: NSSize(width: textWidth - 10, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let textHeight = min(max(ceil(measured.height) + 16, 60), 320)
    let height = padding + textHeight + 12 + buttonHeight + padding

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.title = "Review Polish"
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    // Panels hide when their app is inactive by default; TextPolish never becomes active here.
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.delegate = self

    let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    let scrollView = NSScrollView(frame: NSRect(x: padding, y: padding + buttonHeight + 12, width: textWidth, height: textHeight))
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder
    let textView = NSTextView(frame: scrollView.bounds)
    textView.isEditable = false
    textView.isSelectable = true
    textView.textContainerInset = NSSize(width: 4, height: 6)
    textView.autoresizingMask = [.width]
    textView.textStorage?.setAttributedString(text)
    textView.setAccessibilityLabel("Changes made by Polish")
    scrollView.documentView = textView
    content.addSubview(scrollView)

    let pasteButton = NSButton(title: "Paste", target: self, action: #selector(paste))
    pasteButton.keyEquivalent = "\r"
    pasteButton.frame = NSRect(x: width - padding - 96, y: padding, width: 96, height: buttonHeight)
    content.addSubview(pasteButton)

    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.frame = NSRect(x: width - padding - 96 - 8 - 96, y: padding, width: 96, height: buttonHeight)
    content.addSubview(cancelButton)

    let hint = NSTextField(labelWithString: "Return pastes, Escape cancels")
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    hint.frame = NSRect(x: padding, y: padding + 8, width: 220, height: 16)
    content.addSubview(hint)

    panel.contentView = content
    panel.center()
    self.panel = panel
    panel.makeKeyAndOrderFront(nil)
  }

  #if DEBUG
    var debugIsShowing: Bool {
      panel != nil
    }

    /// Whether the panel keeps the polished app in front and stays visible while TextPolish is inactive.
    var debugStaysOverOtherApps: Bool {
      guard let panel else { return false }
      return panel.styleMask.contains(.nonactivatingPanel) && !panel.hidesOnDeactivate && panel.level == .floating
    }

    func debugChoose(paste approved: Bool) {
      finish(approved: approved)
    }
  #endif
}
