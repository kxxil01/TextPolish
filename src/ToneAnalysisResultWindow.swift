import AppKit

@MainActor
protocol ToneAnalysisResultPresenter {
  func showResult(_ result: ToneAnalysisResult)
  func showError(_ message: String)
  func dismiss()
}

@MainActor
final class ToneAnalysisResultWindow: NSPanel, ToneAnalysisResultPresenter {
  private let scrollView = NSScrollView()
  private let contentStack = NSStackView()
  private let meaningLabel = NSTextField(wrappingLabelWithString: "")
  private let intentLabel = NSTextField(wrappingLabelWithString: "")
  private let sentimentLabel = NSTextField(labelWithString: "")
  private let formalityLabel = NSTextField(labelWithString: "")
  private let toneLabel = NSTextField(labelWithString: "")
  private let keyPhrasesStack = NSStackView()
  private let riskLabel = NSTextField(labelWithString: "")
  private let riskReasonLabel = NSTextField(wrappingLabelWithString: "")
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

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    containerView.addSubview(scrollView)

    let clipView = NSClipView()
    clipView.drawsBackground = false
    scrollView.contentView = clipView

    let documentView = NSView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = documentView

    contentStack.orientation = .vertical
    contentStack.alignment = .leading
    contentStack.spacing = 6
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
    documentView.addSubview(contentStack)

    addSection("What it means")
    meaningLabel.font = NSFont.systemFont(ofSize: 12)
    meaningLabel.textColor = .labelColor
    meaningLabel.preferredMaxLayoutWidth = 340
    meaningLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(meaningLabel)

    addSection("Intent")
    intentLabel.font = NSFont.systemFont(ofSize: 12)
    intentLabel.textColor = .labelColor
    intentLabel.preferredMaxLayoutWidth = 340
    intentLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(intentLabel)

    addSpacer(4)

    let badgeRow = NSStackView()
    badgeRow.orientation = .horizontal
    badgeRow.spacing = 8
    badgeRow.alignment = .centerY
    badgeRow.addArrangedSubview(makeBadgeLabel("Tone:", valueLabel: toneLabel))
    badgeRow.addArrangedSubview(makeBadgeLabel("Sentiment:", valueLabel: sentimentLabel))
    badgeRow.addArrangedSubview(makeBadgeLabel("Formality:", valueLabel: formalityLabel))
    contentStack.addArrangedSubview(badgeRow)

    addSeparator()
    addSection("Key Phrases")
    keyPhrasesStack.orientation = .vertical
    keyPhrasesStack.alignment = .leading
    keyPhrasesStack.spacing = 4
    keyPhrasesStack.translatesAutoresizingMaskIntoConstraints = false
    contentStack.addArrangedSubview(keyPhrasesStack)

    addSeparator()
    addSection("Misunderstanding Risk")
    let riskRow = NSStackView()
    riskRow.orientation = .horizontal
    riskRow.spacing = 6
    riskRow.alignment = .firstBaseline
    riskRow.addArrangedSubview(riskLabel)
    riskReasonLabel.font = NSFont.systemFont(ofSize: 11)
    riskReasonLabel.textColor = .secondaryLabelColor
    riskReasonLabel.preferredMaxLayoutWidth = 280
    riskReasonLabel.lineBreakMode = .byWordWrapping
    riskRow.addArrangedSubview(riskReasonLabel)
    contentStack.addArrangedSubview(riskRow)

    addSeparator()
    addSection("Ambiguities")
    ambiguitiesLabel.font = NSFont.systemFont(ofSize: 12)
    ambiguitiesLabel.textColor = .secondaryLabelColor
    ambiguitiesLabel.preferredMaxLayoutWidth = 340
    ambiguitiesLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(ambiguitiesLabel)

    addSeparator()
    addSection("Suggested Replies")
    repliesLabel.font = NSFont.systemFont(ofSize: 12)
    repliesLabel.textColor = .secondaryLabelColor
    repliesLabel.preferredMaxLayoutWidth = 340
    repliesLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(repliesLabel)

    addSpacer(8)
    closeButton.target = self
    closeButton.action = #selector(closeButtonClicked)
    closeButton.keyEquivalent = "\r"
    closeButton.bezelStyle = .rounded
    contentStack.addArrangedSubview(closeButton)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
      scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
      contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
      contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
      contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
      contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
      documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
      containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 380),
      containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
      containerView.heightAnchor.constraint(lessThanOrEqualToConstant: 520),
    ])
  }

  private func addSection(_ title: String) {
    let label = NSTextField(labelWithString: title)
    label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .tertiaryLabelColor
    contentStack.addArrangedSubview(label)
  }

  private func addSeparator() {
    let sep = NSBox()
    sep.boxType = .separator
    sep.translatesAutoresizingMaskIntoConstraints = false
    contentStack.addArrangedSubview(sep)
    sep.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -40).isActive = true
  }

  private func addSpacer(_ height: CGFloat) {
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
    contentStack.addArrangedSubview(spacer)
  }

  private func makeBadgeLabel(_ title: String, valueLabel: NSTextField) -> NSStackView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.spacing = 3
    row.alignment = .firstBaseline
    let titleField = NSTextField(labelWithString: title)
    titleField.font = NSFont.systemFont(ofSize: 10, weight: .medium)
    titleField.textColor = .tertiaryLabelColor
    titleField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    valueLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    valueLabel.textColor = .labelColor
    row.addArrangedSubview(titleField)
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
    toneLabel.stringValue = "\(toneEmoji(result.tone)) \(result.tone.rawValue)"
    sentimentLabel.stringValue = sentimentEmoji(result.sentiment) + " " + result.sentiment.displayName
    formalityLabel.stringValue = result.formality.displayName

    riskLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
    riskLabel.stringValue = result.misunderstandingRisk.level.displayName
    riskLabel.textColor = riskColor(result.misunderstandingRisk.level)
    riskReasonLabel.stringValue = result.misunderstandingRisk.reason

    populateKeyPhrases(result.keyPhrases)
    ambiguitiesLabel.stringValue = formatList(result.ambiguities, emptyFallback: "None identified.")
    repliesLabel.stringValue = formatList(result.suggestedReplies, emptyFallback: "No reply suggestion.")

    sizeToFitContent()
    positionNearCursor()
    makeKeyAndOrderFront(nil)
  }

  func showError(_ message: String) {
    ensureEscapeMonitor()
    meaningLabel.stringValue = message
    intentLabel.stringValue = "-"
    toneLabel.stringValue = "Error"
    sentimentLabel.stringValue = "-"
    formalityLabel.stringValue = "-"
    riskLabel.stringValue = "-"
    riskReasonLabel.stringValue = "-"
    populateKeyPhrases([])
    ambiguitiesLabel.stringValue = "-"
    repliesLabel.stringValue = "-"

    sizeToFitContent()
    positionNearCursor()
    makeKeyAndOrderFront(nil)
  }

  private func populateKeyPhrases(_ phrases: [KeyPhrase]) {
    keyPhrasesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    guard !phrases.isEmpty else {
      let none = NSTextField(labelWithString: "All phrases are straightforward.")
      none.font = NSFont.systemFont(ofSize: 12)
      none.textColor = .secondaryLabelColor
      keyPhrasesStack.addArrangedSubview(none)
      return
    }
    for kp in phrases {
      let row = NSTextField(wrappingLabelWithString: "\"\(kp.phrase)\" — \(kp.meaning)")
      row.font = NSFont.systemFont(ofSize: 12)
      row.textColor = .labelColor
      row.preferredMaxLayoutWidth = 340
      row.lineBreakMode = .byWordWrapping
      keyPhrasesStack.addArrangedSubview(row)
    }
  }

  private func sizeToFitContent() {
    guard let documentView = scrollView.documentView else { return }
    documentView.layoutSubtreeIfNeeded()
    let intrinsicHeight = contentStack.fittingSize.height
    let maxHeight: CGFloat = 520
    let targetHeight = min(intrinsicHeight, maxHeight)
    setContentSize(NSSize(width: frame.width, height: targetHeight))
  }

  private func riskColor(_ level: MisunderstandingRiskLevel) -> NSColor {
    switch level {
    case .low: return .systemGreen
    case .medium: return .systemOrange
    case .high: return .systemRed
    }
  }

  private func sentimentEmoji(_ sentiment: Sentiment) -> String {
    switch sentiment {
    case .positive: return "👍"
    case .neutral: return "➖"
    case .negative: return "👎"
    }
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
