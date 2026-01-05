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
  private let toneLabel = NSTextField(labelWithString: "")
  private let sentimentLabel = NSTextField(labelWithString: "")
  private let formalityLabel = NSTextField(labelWithString: "")
  private let explanationLabel = NSTextField(wrappingLabelWithString: "")
  private let closeButton = NSButton(title: "Close", target: nil, action: nil)

  private var localMonitor: Any?

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
    title = "Tone Analysis"
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    level = .floating
    isMovableByWindowBackground = true
    backgroundColor = NSColor.windowBackgroundColor
    hasShadow = true

    // Auto-dismiss on Escape
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { // Escape
        self?.dismiss()
        return nil
      }
      return event
    }
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

    // Tone row
    let toneRow = makeRow(label: "Tone:", valueLabel: toneLabel)
    contentStack.addArrangedSubview(toneRow)

    // Sentiment row
    let sentimentRow = makeRow(label: "Sentiment:", valueLabel: sentimentLabel)
    contentStack.addArrangedSubview(sentimentRow)

    // Formality row
    let formalityRow = makeRow(label: "Formality:", valueLabel: formalityLabel)
    contentStack.addArrangedSubview(formalityRow)

    // Separator
    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    contentStack.addArrangedSubview(separator)
    separator.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -40).isActive = true

    // Explanation
    explanationLabel.font = NSFont.systemFont(ofSize: 12)
    explanationLabel.textColor = .secondaryLabelColor
    explanationLabel.preferredMaxLayoutWidth = 260
    explanationLabel.lineBreakMode = .byWordWrapping
    contentStack.addArrangedSubview(explanationLabel)

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

  @objc private func closeButtonClicked() {
    dismiss()
  }

  func showResult(_ result: ToneAnalysisResult) {
    toneLabel.stringValue = "\(toneEmoji(result.tone)) \(result.tone.rawValue)"
    sentimentLabel.stringValue = "\(sentimentEmoji(result.sentiment)) \(result.sentiment.rawValue)"
    formalityLabel.stringValue = result.formality.rawValue
    explanationLabel.stringValue = result.explanation

    positionNearCursor()
    makeKeyAndOrderFront(nil)
  }

  func showError(_ message: String) {
    toneLabel.stringValue = "Error"
    sentimentLabel.stringValue = "-"
    formalityLabel.stringValue = "-"
    explanationLabel.stringValue = message

    positionNearCursor()
    makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    orderOut(nil)
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

    // Ensure window stays on screen
    let screenFrame = screen.visibleFrame
    if newOrigin.x + windowSize.width > screenFrame.maxX {
      newOrigin.x = mouseLocation.x - windowSize.width - 20
    }
    if newOrigin.y < screenFrame.minY {
      newOrigin.y = mouseLocation.y + 20
    }
    if newOrigin.x < screenFrame.minX {
      newOrigin.x = screenFrame.minX + 20
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

  private func sentimentEmoji(_ sentiment: Sentiment) -> String {
    switch sentiment {
    case .positive: return "👍"
    case .negative: return "👎"
    case .neutral: return "➖"
    case .mixed: return "🔀"
    }
  }

  deinit {
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
