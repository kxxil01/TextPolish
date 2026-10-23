import AppKit

/// What the user chose in the preview.
enum PolishReviewDecision: Equatable, Sendable {
  case paste
  case cancel
  /// Polish the original again in this style.
  case retry(CorrectionStyle)
}

/// A style the preview offers for another try.
struct PolishStyleChoice: Equatable, Sendable {
  let name: String
  let style: CorrectionStyle
}

/// Asks the user to confirm a Polish result before it replaces their text.
@MainActor
protocol PolishReviewing: AnyObject {
  /// Shows the result and waits for Paste, Cancel, or another try. Empty `choices` hides the style picker.
  /// A `warning` says what a check flagged; Return then no longer pastes, so pasting takes a deliberate click.
  func review(
    original: String,
    polished: String,
    style: CorrectionStyle,
    choices: [PolishStyleChoice],
    warning: String?
  ) async -> PolishReviewDecision
  /// Closes the panel without a choice, for example when another try fails.
  func dismiss()
}

/// A small panel with the changes highlighted: Return pastes, Escape or closing cancels, and Try Again or
/// another style polishes the original again while the panel stays up.
/// It takes keyboard input without activating TextPolish, so the app being polished stays in front.
@MainActor
final class PolishReviewPanel: NSObject, PolishReviewing, NSWindowDelegate {
  private var panel: NSPanel?
  private var continuation: CheckedContinuation<PolishReviewDecision, Never>?
  private var currentStyle: CorrectionStyle = .clarify
  private var choices: [PolishStyleChoice] = []
  private var warning: String?
  private var textView: NSTextView?
  private var stylePopup: NSPopUpButton?
  private var actionButtons: [NSButton] = []
  /// Cancel was pressed while another try ran; the next review returns Cancel without showing anything.
  private var canceledWhileWorking = false

  func review(
    original: String,
    polished: String,
    style: CorrectionStyle,
    choices: [PolishStyleChoice],
    warning: String? = nil
  ) async -> PolishReviewDecision {
    resolve(.cancel)
    if canceledWhileWorking {
      dismiss()
      return .cancel
    }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        self.continuation = continuation
        self.currentStyle = style
        self.choices = choices
        self.warning = warning
        self.show(original: original, polished: polished)
      }
    } onCancel: {
      Task { @MainActor in
        self.resolve(.cancel)
        self.dismiss()
      }
    }
  }

  func dismiss() {
    canceledWhileWorking = false
    close()
  }

  func windowWillClose(_: Notification) {
    cancel()
  }

  @objc private func paste() {
    resolve(.paste)
    close()
  }

  @objc private func cancel() {
    if continuation == nil, panel != nil {
      canceledWhileWorking = true
    }
    resolve(.cancel)
    close()
  }

  @objc private func tryAgain() {
    retry(currentStyle)
  }

  @objc private func styleChosen(_ sender: NSPopUpButton) {
    guard choices.indices.contains(sender.indexOfSelectedItem) else { return }
    retry(choices[sender.indexOfSelectedItem].style)
  }

  /// Keeps the panel up, showing progress, while the controller polishes again.
  private func retry(_ style: CorrectionStyle) {
    guard continuation != nil else { return }
    let name = choices.first { $0.style == style }?.name
    let message = name.map { "Polishing as \($0)\u{2026}" } ?? "Trying again\u{2026}"
    textView?.textStorage?.setAttributedString(NSAttributedString(
      string: message,
      attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor]
    ))
    stylePopup?.isEnabled = false
    actionButtons.forEach { $0.isEnabled = false }
    resolve(.retry(style))
  }

  private func resolve(_ decision: PolishReviewDecision) {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(returning: decision)
  }

  private func close() {
    guard let panel else { return }
    panel.delegate = nil
    panel.orderOut(nil)
    self.panel = nil
    textView = nil
    stylePopup = nil
    actionButtons = []
  }

  private func show(original: String, polished: String) {
    let width: CGFloat = 600
    let padding: CGFloat = 16
    let buttonHeight: CGFloat = 32
    let font = NSFont.systemFont(ofSize: 14)
    let isTranslation = currentStyle.translatesToEnglish
    // Every word of a translation changes, so a diff would only be noise.
    let text = isTranslation
      ? NSAttributedString(string: polished, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
      : WordDiff.attributedString(from: WordDiff.changes(from: original, to: polished), font: font)

    let textWidth = width - padding * 2
    let measured = text.boundingRect(
      with: NSSize(width: textWidth - 10, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let textHeight = min(max(ceil(measured.height) + 16, 60), 320)
    let warningLabel = warning.map(Self.warningLabel)
    let warningHeight = warningLabel.map { label in
      ceil(label.attributedStringValue.boundingRect(
        with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
      ).height) + 10
    } ?? 0
    let height = padding + textHeight + 12 + buttonHeight + padding + warningHeight

    // Another try replaces the panel in the same spot.
    let previousTopLeft = panel.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
    close()

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    switch currentStyle {
    case .translateToEnglish: panel.title = "Review Translation"
    case .reply: panel.title = "Review Reply"
    default: panel.title = "Review Polish"
    }
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
    textView.setAccessibilityLabel(isTranslation ? "Translation" : "Changes made by Polish")
    scrollView.documentView = textView
    content.addSubview(scrollView)
    self.textView = textView
    if let warningLabel {
      warningLabel.frame = NSRect(x: padding, y: height - padding - warningHeight + 6, width: textWidth, height: warningHeight - 6)
      content.addSubview(warningLabel)
    }

    addButtons(to: content, width: width, padding: padding, buttonHeight: buttonHeight)

    panel.contentView = content
    if let previousTopLeft {
      panel.setFrameTopLeftPoint(previousTopLeft)
    } else {
      panel.center()
    }
    self.panel = panel
    panel.makeKeyAndOrderFront(nil)
  }

  /// Style picker and Try Again on the left; Cancel and Paste on the right.
  private func addButtons(to content: NSView, width: CGFloat, padding: CGFloat, buttonHeight: CGFloat) {
    var x = padding
    if !choices.isEmpty {
      let popup = NSPopUpButton(frame: NSRect(x: x, y: padding + 2, width: 150, height: 28), pullsDown: false)
      popup.addItems(withTitles: choices.map(\.name))
      if let index = choices.firstIndex(where: { $0.style == currentStyle }) {
        popup.selectItem(at: index)
      }
      popup.target = self
      popup.action = #selector(styleChosen(_:))
      popup.toolTip = "Polish again in another style"
      popup.setAccessibilityLabel("Style")
      content.addSubview(popup)
      stylePopup = popup
      x += 150 + 8
    }

    let tryAgainButton = NSButton(title: "Try Again", target: self, action: #selector(tryAgain))
    tryAgainButton.frame = NSRect(x: x, y: padding, width: 100, height: buttonHeight)
    tryAgainButton.toolTip = "Ask for another version"
    content.addSubview(tryAgainButton)

    let pasteButton = NSButton(title: "Paste", target: self, action: #selector(paste))
    // A flagged result is pasted only with a deliberate click.
    pasteButton.keyEquivalent = warning == nil ? "\r" : ""
    pasteButton.frame = NSRect(x: width - padding - 96, y: padding, width: 96, height: buttonHeight)
    pasteButton.toolTip = "Return pastes, Escape cancels"
    content.addSubview(pasteButton)

    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.frame = NSRect(x: width - padding - 96 - 8 - 96, y: padding, width: 96, height: buttonHeight)
    content.addSubview(cancelButton)

    actionButtons = [tryAgainButton, pasteButton]
  }

  private static func warningLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = .systemOrange
    label.setAccessibilityLabel("Warning")
    return label
  }

  #if DEBUG
    var debugWarning: String? {
      panel == nil ? nil : warning
    }

    var debugIsShowing: Bool {
      panel != nil
    }

    /// Whether the panel keeps the polished app in front and stays visible while TextPolish is inactive.
    var debugStaysOverOtherApps: Bool {
      guard let panel else { return false }
      return panel.styleMask.contains(.nonactivatingPanel) && !panel.hidesOnDeactivate && panel.level == .floating
    }

    var debugTitle: String? {
      panel?.title
    }

    var debugText: String? {
      textView?.string
    }

    var debugStyleNames: [String]? {
      stylePopup?.itemTitles
    }

    func debugChoose(paste approved: Bool) {
      if approved {
        paste()
      } else {
        cancel()
      }
    }

    func debugTryAgain() {
      tryAgain()
    }

    func debugChooseStyle(named name: String) {
      guard let stylePopup else { return }
      stylePopup.selectItem(withTitle: name)
      styleChosen(stylePopup)
    }
  #endif
}
