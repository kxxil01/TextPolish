import AppKit

@MainActor
protocol ToneAnalysisResultPresenter {
  func showResult(_ result: ToneAnalysisResult)
  func showError(_ message: String)
  func dismiss()
}

@MainActor
final class ToneAnalysisResultWindow: NSPanel, ToneAnalysisResultPresenter {
  private let contentStack = NSStackView()
  private let meaningLabel = NSTextField(wrappingLabelWithString: "")
  private let intentLabel = NSTextField(wrappingLabelWithString: "")
  private let riskLabel = NSTextField(labelWithString: "")
  private let riskReasonLabel = NSTextField(wrappingLabelWithString: "")
  private let toneLabel = NSTextField(labelWithString: "")
  private let ambiguitiesLabel = NSTextField(wrappingLabelWithString: "")
  private let repliesLabel = NSTextField(wrappingLabelWithString: "")
  private let closeButton = NSButton(title: "Close", target: nil, action: nil)

  private nonisolated(unsafe) var localMonitor: Any?

  override init(
    contentRect: NSRect,
    styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType,
    defer flag: Bool
  ) {
    super.init(
      contentRect: contentRect,
      styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    setupWindow()
    setupUI()
  }

  private func setupWindow() {
    title = "Message Analysis"
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    level = .floating
    isMovableByWindowBackground = true
    backgroundColor = NSColor.windowBackgroundColor
    hasShadow = true
  }

  private func setupUI() {
    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    contentView = containerView

    contentStack.orientation = .vertical
    contentStack.alignment = .leading
    contentStack.spacing = 12
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
    containerView.addSubview(contentStack)

    // Meaning summary
    let meaningTitle = NSTextField(labelWithString: "Meaning:")
    meaningTitle.font = NSFont.boldSystemFont(ofSize: 13)
    meaningTitle.textColor = .labelColor
    contentStack.addArrangedSubview(meaningTitle)
    meaningLabel.font = NSFont.systemFont(ofSize: 12)
    meaningLabel.textColor = .labelColor
    meaningLabel.preferredMaxLayoutWidth = 300
    meaningLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(meaningLabel)

    // Intent summary
    let intentTitle = NSTextField(labelWithString: "Likely Intent:")
    intentTitle.font = NSFont.boldSystemFont(ofSize: 13)
    intentTitle.textColor = .labelColor
    contentStack.addArrangedSubview(intentTitle)
    intentLabel.font = NSFont.systemFont(ofSize: 12)
    intentLabel.textColor = .labelColor
    intentLabel.preferredMaxLayoutWidth = 300
    intentLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(intentLabel)

    // Misunderstanding risk
    let riskRow = makeRow(label: "Misunderstanding Risk:", valueLabel: riskLabel)
    riskLabel.textColor = .systemOrange
    contentStack.addArrangedSubview(riskRow)
    riskReasonLabel.font = NSFont.systemFont(ofSize: 12)
    riskReasonLabel.textColor = .secondaryLabelColor
    riskReasonLabel.preferredMaxLayoutWidth = 300
    riskReasonLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(riskReasonLabel)

    // Tone row
    let toneRow = makeRow(label: "Tone:", valueLabel: toneLabel)
    contentStack.addArrangedSubview(toneRow)

    // Ambiguities
    let ambiguitiesTitle = NSTextField(labelWithString: "Ambiguities:")
    ambiguitiesTitle.font = NSFont.boldSystemFont(ofSize: 13)
    ambiguitiesTitle.textColor = .labelColor
    contentStack.addArrangedSubview(ambiguitiesTitle)
    ambiguitiesLabel.font = NSFont.systemFont(ofSize: 12)
    ambiguitiesLabel.textColor = .secondaryLabelColor
    ambiguitiesLabel.preferredMaxLayoutWidth = 300
    ambiguitiesLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(ambiguitiesLabel)

    // Suggested replies
    let repliesTitle = NSTextField(labelWithString: "Suggested Replies:")
    repliesTitle.font = NSFont.boldSystemFont(ofSize: 13)
    repliesTitle.textColor = .labelColor
    contentStack.addArrangedSubview(repliesTitle)
    repliesLabel.font = NSFont.systemFont(ofSize: 12)
    repliesLabel.textColor = .secondaryLabelColor
    repliesLabel.preferredMaxLayoutWidth = 300
    repliesLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(repliesLabel)

    // Separator
    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    contentStack.addArrangedSubview(separator)
    separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -40).isActive = true

    // Close button
    closeButton.target = self
    closeButton.action = #selector(closeButtonClicked)
    closeButton.keyEquivalent = "\r"
    closeButton.bezelStyle = .rounded
    contentStack.addArrangedSubview(closeButton)

    // Constraints
    NSLayoutConstraint.activate([
      contentStack.topAnchor.constraint(equalTo: containerView.topAnchor),
      contentStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      contentStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      contentStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
      containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
    ])
  }

  private func makeRow(label: String, valueLabel: NSTextField) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.spacing = 8
    row.alignment = .firstBaseline

    let labelField = NSTextField(labelWithString: label)
    labelField.font = NSFont.boldSystemFont(ofSize: 13)
    labelField.textColor = .labelColor
    labelField.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    valueLabel.font = NSFont.systemFont(ofSize: 13)
    valueLabel.textColor = .labelColor

    row.addArrangedSubview(labelField)
    row.addArrangedSubview(valueLabel)

    return row
  }

  var hasActiveEscapeMonitor: Bool {
    localMonitor != nil
  }

  @objc private func closeButtonClicked() {
    dismiss()
  }

  func showResult(_ result: ToneAnalysisResult) {
    ensureEscapeMonitor()
    meaningLabel.stringValue = result.plainMeaning
    intentLabel.stringValue = result.likelyIntent
    riskLabel.stringValue = result.misunderstandingRisk.level.displayName
    riskReasonLabel.stringValue = result.misunderstandingRisk.reason
    toneLabel.stringValue = "\(toneEmoji(result.tone)) \(result.tone.rawValue)"
    ambiguitiesLabel.stringValue = formatList(result.ambiguities, emptyFallback: "None identified.")
    repliesLabel.stringValue = formatList(result.suggestedReplies, emptyFallback: "No reply suggestion.")

    positionNearCursor()
    makeKeyAndOrderFront(nil)
  }

  func showError(_ message: String) {
    ensureEscapeMonitor()
    meaningLabel.stringValue = message
    intentLabel.stringValue = "-"
    riskLabel.stringValue = "-"
    riskReasonLabel.stringValue = "-"
    toneLabel.stringValue = "Error"
    ambiguitiesLabel.stringValue = "-"
    repliesLabel.stringValue = "-"

    positionNearCursor()
    makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    removeEscapeMonitorIfNeeded()
    orderOut(nil)
  }

  private func ensureEscapeMonitor() {
    guard localMonitor == nil else { return }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self = self else { return event }
      guard self.isVisible else { return event }
      if event.keyCode == 53 { // Escape
        self.dismiss()
        return nil
      }
      return event
    }
  }

  private nonisolated func removeEscapeMonitorIfNeeded() {
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
      localMonitor = nil
    }
  }

  private func positionNearCursor() {
    let mouseLocation = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main else {
      center()
      return
    }

    let windowSize = frame.size
    var newOrigin = NSPoint(
      x: mouseLocation.x + 20,
      y: mouseLocation.y - windowSize.height - 20
    )

    // Ensure entire window stays on screen
    let screenFrame = screen.visibleFrame

    // Adjust X position if window would be off-screen horizontally
    if newOrigin.x + windowSize.width > screenFrame.maxX {
      newOrigin.x = screenFrame.maxX - windowSize.width - 10
    }
    if newOrigin.x < screenFrame.minX {
      newOrigin.x = screenFrame.minX + 10
    }

    // Adjust Y position if window would be off-screen vertically
    if newOrigin.y < screenFrame.minY {
      newOrigin.y = screenFrame.minY + 10
    }
    if newOrigin.y + windowSize.height > screenFrame.maxY {
      newOrigin.y = mouseLocation.y + 20
    }

    setFrameOrigin(newOrigin)
  }

  private func toneEmoji(_ tone: DetectedTone) -> String {
    switch tone {
    case .friendly: return "😊"
    case .frustrated: return "😤"
    case .formal: return "🎩"
    case .casual: return "👋"
    case .direct: return "➡️"
    case .neutral: return "😐"
    case .sarcastic: return "😏"
    case .enthusiastic: return "🎉"
    case .concerned: return "😟"
    case .professional: return "💼"
    }
  }

  private func formatList(_ values: [String], emptyFallback: String) -> String {
    guard !values.isEmpty else { return emptyFallback }
    return values.map { "• \($0)" }.joined(separator: "\n")
  }

  deinit {
    removeEscapeMonitorIfNeeded()
  }
}
