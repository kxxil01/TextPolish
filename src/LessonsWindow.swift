import AppKit

/// Lists recent Learn mode explanations, newest first, with a button to clear them.
@MainActor
final class LessonsWindow: NSPanel {
  private let textView = NSTextView()
  private let history: LessonHistory

  init(history: LessonHistory) {
    self.history = history
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    title = "Recent Lessons"
    isFloatingPanel = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    level = .floating
    minSize = NSSize(width: 360, height: 240)
    setupUI()
  }

  func show() {
    reload()
    center()
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
  }

  func reload() {
    textView.textStorage?.setAttributedString(Self.formatted(
      history.lessons, progress: history.progressSummary(), repeated: history.repeatedMistakes()
    ))
  }

  /// This week's progress, then repeated mistakes under "Watch Out For", then each lesson's time as a heading
  /// and its changes, all in Learn panel colors.
  static func formatted(
    _ lessons: [Lesson],
    progress: [String] = [],
    repeated: [RepeatedMistake] = [],
    now: Date = Date()
  ) -> NSAttributedString {
    guard !lessons.isEmpty else {
      return NSAttributedString(
        string: "No lessons yet. Turn on Learn in Settings > Advanced, then Polish some text.",
        attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
      )
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    let headingStyle = NSMutableParagraphStyle()
    headingStyle.paragraphSpacingBefore = 14
    let result = NSMutableAttributedString()
    if !progress.isEmpty {
      result.append(NSAttributedString(string: "This Week\n", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]))
      result.append(NSAttributedString(
        string: progress.joined(separator: "\n") + "\n",
        attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
      ))
    }
    if !repeated.isEmpty {
      result.append(NSAttributedString(string: "Watch Out For\n", attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]))
      result.append(LearnPanel.formatted(repeated.map(\.line)))
      result.append(NSAttributedString(string: "\n"))
    }
    for (index, lesson) in lessons.enumerated() {
      let heading = formatter.localizedString(for: lesson.date, relativeTo: now).capitalizedFirstLetter
      var headingAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
      if index > 0 || !repeated.isEmpty || !progress.isEmpty {
        headingAttributes[.paragraphStyle] = headingStyle
      }
      result.append(NSAttributedString(string: (index > 0 ? "\n" : "") + heading + "\n", attributes: headingAttributes))
      result.append(LearnPanel.formatted(lesson.lines))
    }
    return result
  }

  @objc private func clearClicked() {
    history.clear()
    reload()
  }

  @objc private func closeClicked() {
    orderOut(nil)
  }

  private func setupUI() {
    let container = NSView()
    contentView = container

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.borderType = .bezelBorder
    scrollView.hasVerticalScroller = true
    textView.isEditable = false
    textView.isSelectable = true
    textView.textContainerInset = NSSize(width: 10, height: 10)
    textView.autoresizingMask = [.width]
    textView.isVerticallyResizable = true
    textView.textContainer?.widthTracksTextView = true
    scrollView.documentView = textView

    let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearClicked))
    let closeButton = NSButton(title: "Close", target: self, action: #selector(closeClicked))
    closeButton.keyEquivalent = "\r"
    let buttons = NSStackView(views: [clearButton, closeButton])
    buttons.translatesAutoresizingMaskIntoConstraints = false
    buttons.spacing = 8

    container.addSubview(scrollView)
    container.addSubview(buttons)
    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      buttons.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
      buttons.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      buttons.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
    ])
  }
}

private extension String {
  var capitalizedFirstLetter: String {
    prefix(1).uppercased() + dropFirst()
  }
}
