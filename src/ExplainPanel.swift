import AppKit

/// Shows what a received message means, without taking focus from the app it is in.
@MainActor
protocol MessageExplanationPresenting: AnyObject {
  /// Opens right away, so a slow answer never looks like nothing happened.
  func showLoading()
  func show(explanation: MessageExplanation)
  func showError(_ message: String)
}

/// Explain Message's panel: the meaning, tone, and phrases, then ways to answer. Quick reply buttons or the
/// writer's own words produce an English reply they can edit, then Paste into the app or Copy.
/// It floats without activating TextPolish, so the app being answered stays in front, and closes on Escape,
/// its close button, or Paste.
@MainActor
final class ExplainPanel: NSObject, MessageExplanationPresenting, NSWindowDelegate {
  var onIntent: ((ReplyIntent) -> Void)?
  var onDraft: ((String) -> Void)?
  var onPaste: ((String) -> Void)?
  var onCopy: ((String) -> Void)?

  private static let width: CGFloat = 420
  private static let padding: CGFloat = 14
  private static let maxExplanationHeight: CGFloat = 240

  private var panel: NSPanel?
  private let stack = NSStackView()
  private let explanationView = NSTextView()
  private let explanationScroll = NSScrollView()
  private var explanationHeight: NSLayoutConstraint?
  private let answerSection = NSStackView()
  private let draftField = NSTextField()
  private let resultSection = NSStackView()
  private let resultStatus = NSTextField(labelWithString: "")
  private let replyView = NSTextView()
  private let replyScroll = NSScrollView()
  private let replyButtons = NSStackView()

  override init() {
    super.init()
    buildContent()
  }

  // MARK: Explanation

  func showLoading() {
    setExplanation(NSAttributedString(
      string: "Explaining\u{2026}",
      attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
    ))
    answerSection.isHidden = true
    resultSection.isHidden = true
    draftField.stringValue = ""
    present()
  }

  func show(explanation: MessageExplanation) {
    setExplanation(Self.formatted(explanation))
    answerSection.isHidden = false
    resultSection.isHidden = true
    present()
  }

  func showError(_ message: String) {
    setExplanation(Self.errorText(message))
    answerSection.isHidden = true
    resultSection.isHidden = true
    present()
  }

  // MARK: Reply

  func showWritingReply() {
    resultStatus.stringValue = "Writing reply\u{2026}"
    replyScroll.isHidden = true
    replyButtons.isHidden = true
    resultSection.isHidden = false
    fitToContent()
  }

  /// The reply stays editable, so placeholders such as [time] can be filled in before pasting.
  func showReply(_ reply: String) {
    resultStatus.stringValue = reply.contains("[") ? "Your reply (fill in the [brackets])" : "Your reply"
    replyView.string = reply
    replyScroll.isHidden = false
    replyButtons.isHidden = false
    resultSection.isHidden = false
    fitToContent()
  }

  func showReplyError(_ message: String) {
    resultStatus.stringValue = message
    replyScroll.isHidden = true
    replyButtons.isHidden = true
    resultSection.isHidden = false
    fitToContent()
  }

  func close() {
    guard let panel else { return }
    panel.delegate = nil
    panel.orderOut(nil)
    self.panel = nil
  }

  func windowWillClose(_: Notification) {
    panel = nil
  }

  // MARK: Actions

  @objc private func intentClicked(_ sender: NSButton) {
    let intents = ReplyIntent.allCases
    guard intents.indices.contains(sender.tag) else { return }
    onIntent?(intents[sender.tag])
  }

  @objc private func writeClicked(_: Any?) {
    let draft = draftField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !draft.isEmpty else { return }
    onDraft?(draft)
  }

  @objc private func pasteClicked(_: Any?) {
    let reply = currentReply
    guard !reply.isEmpty else { return }
    close()
    onPaste?(reply)
  }

  @objc private func copyClicked(_: Any?) {
    let reply = currentReply
    guard !reply.isEmpty else { return }
    onCopy?(reply)
    resultStatus.stringValue = "Copied"
  }

  private var currentReply: String {
    replyView.string.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: Layout

  private func buildContent() {
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding, right: Self.padding)
    stack.translatesAutoresizingMaskIntoConstraints = false

    configure(textView: explanationView, in: explanationScroll, editable: false)
    explanationView.setAccessibilityLabel("What the message means")
    explanationHeight = explanationScroll.heightAnchor.constraint(equalToConstant: 40)
    explanationHeight?.isActive = true
    stack.addArrangedSubview(explanationScroll)

    buildAnswerSection()
    stack.addArrangedSubview(answerSection)
    buildResultSection()
    stack.addArrangedSubview(resultSection)

    let contentWidth = Self.width - Self.padding * 2
    for view in [explanationScroll, answerSection, resultSection] {
      view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    }
  }

  private func buildAnswerSection() {
    answerSection.orientation = .vertical
    answerSection.alignment = .leading
    answerSection.spacing = 8

    let divider = NSBox()
    divider.boxType = .separator
    let heading = Self.heading("Answer")

    let intents = NSStackView(views: ReplyIntent.allCases.enumerated().map { index, intent in
      let button = NSButton(title: intent.title, target: self, action: #selector(intentClicked(_:)))
      button.tag = index
      button.controlSize = .small
      button.bezelStyle = .rounded
      button.toolTip = intent.toolTip
      return button
    })
    intents.spacing = 6

    draftField.placeholderString = "Or type your answer, in any language"
    draftField.target = self
    draftField.action = #selector(writeClicked(_:))
    draftField.setAccessibilityLabel("Your answer")
    let writeButton = NSButton(title: "Write", target: self, action: #selector(writeClicked(_:)))
    writeButton.bezelStyle = .rounded
    let draftRow = NSStackView(views: [draftField, writeButton])
    draftRow.spacing = 8
    draftField.setContentHuggingPriority(.defaultLow, for: .horizontal)

    for view in [divider, heading, intents, draftRow] {
      answerSection.addArrangedSubview(view)
    }
    divider.widthAnchor.constraint(equalTo: answerSection.widthAnchor).isActive = true
    draftRow.widthAnchor.constraint(equalTo: answerSection.widthAnchor).isActive = true
  }

  private func buildResultSection() {
    resultSection.orientation = .vertical
    resultSection.alignment = .leading
    resultSection.spacing = 6

    resultStatus.font = .systemFont(ofSize: 11, weight: .semibold)
    resultStatus.textColor = .secondaryLabelColor
    resultStatus.lineBreakMode = .byWordWrapping
    resultStatus.maximumNumberOfLines = 3

    configure(textView: replyView, in: replyScroll, editable: true)
    replyView.setAccessibilityLabel("Your reply")
    replyScroll.borderType = .bezelBorder
    replyScroll.heightAnchor.constraint(equalToConstant: 64).isActive = true

    let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyClicked(_:)))
    copyButton.bezelStyle = .rounded
    let pasteButton = NSButton(title: "Paste", target: self, action: #selector(pasteClicked(_:)))
    pasteButton.bezelStyle = .rounded
    pasteButton.toolTip = "Pastes into the app you were reading"
    replyButtons.setViews([copyButton, pasteButton], in: .trailing)
    replyButtons.spacing = 8

    for view in [resultStatus, replyScroll, replyButtons] {
      resultSection.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: resultSection.widthAnchor).isActive = true
    }
  }

  private func configure(textView: NSTextView, in scrollView: NSScrollView, editable: Bool) {
    scrollView.drawsBackground = editable
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    textView.isEditable = editable
    textView.isSelectable = true
    textView.isRichText = false
    textView.drawsBackground = editable
    textView.font = .systemFont(ofSize: 13)
    textView.textContainerInset = editable ? NSSize(width: 4, height: 4) : .zero
    textView.textContainer?.lineFragmentPadding = editable ? 4 : 0
    textView.textContainer?.widthTracksTextView = true
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    scrollView.documentView = textView
  }

  private func setExplanation(_ text: NSAttributedString) {
    explanationView.textStorage?.setAttributedString(text)
    let contentWidth = Self.width - Self.padding * 2
    let measured = ceil(text.boundingRect(
      with: NSSize(width: contentWidth - 4, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height) + 4
    // Long explanations scroll instead of growing past the screen.
    explanationHeight?.constant = min(measured, Self.maxExplanationHeight)
  }

  /// Shows the panel at the top right without taking focus; clicking the answer field makes it take typing.
  private func present() {
    if panel == nil {
      let panel = ExplainNSPanel(
        contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
        backing: .buffered,
        defer: false
      )
      panel.title = "What it means"
      panel.isFloatingPanel = true
      panel.level = .floating
      panel.hidesOnDeactivate = false
      panel.becomesKeyOnlyIfNeeded = true
      panel.isReleasedWhenClosed = false
      panel.delegate = self
      let content = NSView()
      content.addSubview(stack)
      NSLayoutConstraint.activate([
        stack.topAnchor.constraint(equalTo: content.topAnchor),
        stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      ])
      panel.contentView = content
      self.panel = panel
      fitToContent()
      if let screen = NSScreen.main {
        let visible = screen.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 16, y: visible.maxY - 16))
      }
    } else {
      fitToContent()
    }
    panel?.orderFrontRegardless()
  }

  /// Resizes to the visible sections, keeping the top edge in place.
  private func fitToContent() {
    guard let panel else { return }
    stack.layoutSubtreeIfNeeded()
    let size = NSSize(width: Self.width, height: stack.fittingSize.height)
    let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    panel.setContentSize(size)
    panel.setFrameTopLeftPoint(topLeft)
  }

  // MARK: Formatting

  /// The meaning first, then the tone, then each phrase with what it means.
  static func formatted(_ explanation: MessageExplanation) -> NSAttributedString {
    let body = NSFont.systemFont(ofSize: 13)
    let spaced = NSMutableParagraphStyle()
    spaced.paragraphSpacingBefore = 8
    let result = NSMutableAttributedString(
      string: explanation.meaning,
      attributes: [.font: body, .foregroundColor: NSColor.labelColor]
    )
    if let tone = explanation.tone {
      result.append(NSAttributedString(
        string: "\nTone: \(tone)",
        attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: spaced]
      ))
    }
    guard !explanation.phrases.isEmpty else { return result }
    result.append(NSAttributedString(
      string: "\nPhrases",
      attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
        .paragraphStyle: spaced,
      ]
    ))
    for phrase in explanation.phrases {
      let parts = phrase.components(separatedBy: "→")
      let term = parts[0].trimmingCharacters(in: .whitespaces)
      result.append(NSAttributedString(
        string: "\n" + term,
        attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor]
      ))
      if parts.count > 1 {
        let meaning = parts.dropFirst().joined(separator: "→").trimmingCharacters(in: .whitespaces)
        result.append(NSAttributedString(string: " → " + meaning, attributes: [.font: body, .foregroundColor: NSColor.labelColor]))
      }
    }
    return result
  }

  private static func errorText(_ message: String) -> NSAttributedString {
    NSAttributedString(
      string: "Couldn't explain this message: \(message)",
      attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
    )
  }

  private static func heading(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
  }

  #if DEBUG
    var debugIsShowing: Bool {
      panel != nil
    }

    var debugExplanationText: String {
      explanationView.string
    }

    var debugShowsAnswerSection: Bool {
      !answerSection.isHidden
    }

    var debugResultStatus: String? {
      resultSection.isHidden ? nil : resultStatus.stringValue
    }

    var debugReply: String {
      replyView.string
    }

    var debugIntentTitles: [String] {
      ReplyIntent.allCases.map(\.title)
    }

    func debugChooseIntent(_ intent: ReplyIntent) {
      let button = NSButton()
      button.tag = ReplyIntent.allCases.firstIndex(of: intent) ?? 0
      intentClicked(button)
    }

    func debugWriteDraft(_ draft: String) {
      draftField.stringValue = draft
      writeClicked(nil)
    }

    func debugEditReply(_ reply: String) {
      replyView.string = reply
    }

    func debugPaste() {
      pasteClicked(nil)
    }

    func debugCopy() {
      copyClicked(nil)
    }
  #endif
}

/// Escape closes the panel, as it does a sheet.
private final class ExplainNSPanel: NSPanel {
  override func cancelOperation(_ sender: Any?) {
    close()
  }
}
