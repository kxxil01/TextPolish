import AppKit

/// Shows what Polish changed and why, without taking focus from the app the user is typing in.
@MainActor
protocol ChangeExplanationPresenting: AnyObject {
  func show(lines: [String])
}

/// Shows what a received message means, without taking focus from the app it is in.
@MainActor
protocol MessageExplanationPresenting: AnyObject {
  func show(explanation: MessageExplanation)
}

/// A small floating panel for Learn mode and Explain Message. It hides after a reading time, stays while hovered,
/// and scrolls when the text is long.
@MainActor
final class LearnPanel: ChangeExplanationPresenting, MessageExplanationPresenting {
  private var panel: NSPanel?
  private var textView: NSTextView?
  private var hideTask: Task<Void, Never>?
  private let fixedVisibleDuration: Duration?
  private let afterHoverDelay: Duration

  /// Leave `visibleDuration` nil to give each change time to be read (see `readingTime(lineCount:)`).
  init(visibleDuration: Duration? = nil, afterHoverDelay: Duration = .seconds(4)) {
    fixedVisibleDuration = visibleDuration
    self.afterHoverDelay = afterHoverDelay
  }

  /// Six seconds plus three per change, at most twenty. Lessons are also saved, so closing early loses nothing.
  nonisolated static func readingTime(lineCount: Int) -> Duration {
    .seconds(min(6 + 3 * lineCount, 20))
  }

  func show(lines: [String]) {
    guard !lines.isEmpty else {
      close()
      return
    }
    show(
      title: "What changed",
      text: Self.formatted(lines),
      accessibilityLabel: "What Polish changed",
      visibleFor: fixedVisibleDuration ?? Self.readingTime(lineCount: lines.count)
    )
  }

  func show(explanation: MessageExplanation) {
    show(
      title: "What it means",
      text: Self.formatted(explanation),
      accessibilityLabel: "What the message means",
      visibleFor: fixedVisibleDuration ?? Self.readingTime(for: explanation)
    )
  }

  /// Eight seconds plus one per 40 characters of meaning and three per phrase, at most 45.
  nonisolated static func readingTime(for explanation: MessageExplanation) -> Duration {
    .seconds(min(8 + explanation.meaning.count / 40 + 3 * explanation.phrases.count, 45))
  }

  private func show(title: String, text: NSAttributedString, accessibilityLabel: String, visibleFor duration: Duration) {
    close()
    let width: CGFloat = 400
    let padding: CGFloat = 14
    let textWidth = width - padding * 2
    let measuredHeight = ceil(text.boundingRect(
      with: NSSize(width: textWidth - 10, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height)
    // Long explanations scroll instead of growing past the screen.
    let textHeight = min(measuredHeight + 4, 360)
    let height = textHeight + padding * 2

    let scrollView = NSScrollView(frame: NSRect(x: padding, y: padding, width: textWidth, height: textHeight))
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = measuredHeight + 4 > textHeight
    let textView = NSTextView(frame: scrollView.bounds)
    textView.isEditable = false
    textView.isSelectable = true
    textView.drawsBackground = false
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.autoresizingMask = [.width]
    textView.textStorage?.setAttributedString(text)
    textView.setAccessibilityLabel(accessibilityLabel)
    scrollView.documentView = textView

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = title
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    // Hovering keeps the panel up while the user reads; leaving starts a short countdown.
    let content = HoverTrackingView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    content.onHoverChange = { [weak self] isInside in
      guard let self else { return }
      if isInside {
        self.cancelHide()
      } else {
        self.scheduleHide(after: self.afterHoverDelay)
      }
    }
    panel.contentView = content
    panel.contentView?.addSubview(scrollView)
    self.textView = textView

    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - 16))
    }
    panel.orderFrontRegardless()
    self.panel = panel

    scheduleHide(after: duration)
  }

  private func cancelHide() {
    hideTask?.cancel()
    hideTask = nil
  }

  private func scheduleHide(after duration: Duration) {
    cancelHide()
    hideTask = Task { [weak self] in
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      self?.close()
    }
  }

  func close() {
    hideTask?.cancel()
    hideTask = nil
    panel?.orderOut(nil)
    panel = nil
    textView = nil
  }

  /// The meaning first, then the tone, then each phrase with what it means.
  static func formatted(_ explanation: MessageExplanation) -> NSAttributedString {
    let body = NSFont.systemFont(ofSize: 13)
    let small = NSFont.systemFont(ofSize: 12)
    let heading = NSFont.systemFont(ofSize: 11, weight: .semibold)
    let spaced = NSMutableParagraphStyle()
    spaced.paragraphSpacingBefore = 8
    let result = NSMutableAttributedString(
      string: explanation.meaning,
      attributes: [.font: body, .foregroundColor: NSColor.labelColor]
    )
    if let tone = explanation.tone {
      result.append(NSAttributedString(
        string: "\nTone: \(tone)",
        attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: spaced]
      ))
    }
    guard !explanation.phrases.isEmpty else { return result }
    result.append(NSAttributedString(
      string: "\nPhrases",
      attributes: [.font: heading, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: spaced]
    ))
    for phrase in explanation.phrases {
      let parts = phrase.components(separatedBy: "→")
      let term = parts[0].trimmingCharacters(in: .whitespaces)
      result.append(NSAttributedString(string: "\n" + term, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]))
      if parts.count > 1 {
        let meaning = parts.dropFirst().joined(separator: "→").trimmingCharacters(in: .whitespaces)
        result.append(NSAttributedString(
          string: " → " + meaning,
          attributes: [.font: body, .foregroundColor: NSColor.labelColor]
        ))
      }
    }
    return result
  }

  /// "before → after: reason" becomes the old words in red, the new words in green, and the reason in grey.
  static func formatted(_ lines: [String]) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: 13)
    let result = NSMutableAttributedString()
    let itemSpacing = NSMutableParagraphStyle()
    itemSpacing.paragraphSpacingBefore = 8
    for (index, line) in lines.enumerated() {
      let itemStart = result.length
      if index > 0 {
        result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
      }
      defer {
        // Space above every item but the first, so each change reads as its own entry.
        if index > 0 {
          result.addAttribute(.paragraphStyle, value: itemSpacing, range: NSRange(location: itemStart + 1, length: 1))
        }
      }
      let arrowParts = line.components(separatedBy: "→")
      guard arrowParts.count >= 2 else {
        result.append(NSAttributedString(string: line, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        continue
      }
      let before = arrowParts[0].trimmingCharacters(in: .whitespaces)
      let afterAndReason = arrowParts.dropFirst().joined(separator: "→")
      let reasonSplit = afterAndReason.range(of: ": ")
      let after = (reasonSplit.map { String(afterAndReason[..<$0.lowerBound]) } ?? afterAndReason)
        .trimmingCharacters(in: .whitespaces)
      let reason = reasonSplit.map { String(afterAndReason[$0.upperBound...]) }

      result.append(NSAttributedString(string: before, attributes: [.font: font, .foregroundColor: NSColor.systemRed]))
      result.append(NSAttributedString(string: " → ", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
      result.append(NSAttributedString(string: after, attributes: [.font: font, .foregroundColor: NSColor.systemGreen]))
      if let reason, !reason.isEmpty {
        let reasonFont = NSFont.systemFont(ofSize: 12)
        result.append(NSAttributedString(
          string: "\n" + reason,
          attributes: [.font: reasonFont, .foregroundColor: NSColor.secondaryLabelColor]
        ))
      }
    }
    return result
  }

  #if DEBUG
    var debugIsShowing: Bool {
      panel != nil
    }

    var debugTitle: String? {
      panel?.title
    }

    var debugText: String? {
      textView?.string
    }

    func debugSimulateHover(inside: Bool) {
      (panel?.contentView as? HoverTrackingView)?.onHoverChange?(inside)
    }
  #endif
}

/// Reports when the pointer enters or leaves the view.
private final class HoverTrackingView: NSView {
  var onHoverChange: ((Bool) -> Void)?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    ))
  }

  override func mouseEntered(with _: NSEvent) {
    onHoverChange?(true)
  }

  override func mouseExited(with _: NSEvent) {
    onHoverChange?(false)
  }
}
