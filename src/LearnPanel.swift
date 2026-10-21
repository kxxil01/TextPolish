import AppKit

/// Shows what Polish changed and why, without taking focus from the app the user is typing in.
@MainActor
protocol ChangeExplanationPresenting: AnyObject {
  func show(lines: [String])
}

@MainActor
final class LearnPanel: ChangeExplanationPresenting {
  private var panel: NSPanel?
  private var hideTask: Task<Void, Never>?
  private let visibleDuration: Duration

  init(visibleDuration: Duration = .seconds(60)) {
    self.visibleDuration = visibleDuration
  }

  func show(lines: [String]) {
    close()
    guard !lines.isEmpty else { return }

    let width: CGFloat = 400
    let padding: CGFloat = 14
    let label = NSTextField(wrappingLabelWithString: "")
    label.attributedStringValue = Self.formatted(lines)
    label.isSelectable = true
    label.setAccessibilityLabel("What Polish changed")
    let textHeight = ceil(label.attributedStringValue.boundingRect(
      with: NSSize(width: width - padding * 2, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height)
    let height = textHeight + padding * 2
    label.frame = NSRect(x: padding, y: padding, width: width - padding * 2, height: textHeight)

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    panel.title = "What changed"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    panel.contentView?.addSubview(label)

    if let screen = NSScreen.main {
      let visible = screen.visibleFrame
      panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - 16))
    }
    panel.orderFrontRegardless()
    self.panel = panel

    let duration = visibleDuration
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
  #endif
}
