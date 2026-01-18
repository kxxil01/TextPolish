import AppKit

@MainActor
final class DiagnosticsWindow: NSPanel, NSWindowDelegate {
  private let textView = NSTextView()
  private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
  private let closeButton = NSButton(title: "Close", target: nil, action: nil)
  private var localMonitor: Any?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
      styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    setupWindow()
    setupUI()
  }

  func update(with snapshot: DiagnosticsSnapshot?) {
    textView.string = DiagnosticsStore.shared.formattedSnapshot()
  }

  func show() {
    update(with: DiagnosticsStore.shared.lastSnapshot)
    installKeyMonitorIfNeeded()
    center()
    makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    removeKeyMonitor()
    orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    removeKeyMonitor()
  }

  private func setupWindow() {
    title = "Diagnostics"
    isFloatingPanel = true
    becomesKeyOnlyIfNeeded = true
    level = .floating
    isMovableByWindowBackground = true
    backgroundColor = NSColor.windowBackgroundColor
    hasShadow = true
    delegate = self
  }

  private func setupUI() {
    let containerView = NSView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    contentView = containerView

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.borderType = .bezelBorder
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false

    textView.isEditable = false
    textView.isSelectable = true
    textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    textView.textColor = .labelColor
    textView.backgroundColor = .textBackgroundColor
    textView.textContainerInset = NSSize(width: 8, height: 8)
    scrollView.documentView = textView

    let buttonStack = NSStackView(views: [copyButton, closeButton])
    buttonStack.orientation = .horizontal
    buttonStack.alignment = .centerY
    buttonStack.spacing = 8
    buttonStack.translatesAutoresizingMaskIntoConstraints = false

    copyButton.target = self
    copyButton.action = #selector(copyClicked)
    copyButton.bezelStyle = .rounded

    closeButton.target = self
    closeButton.action = #selector(closeClicked)
    closeButton.keyEquivalent = "\r"
    closeButton.bezelStyle = .rounded

    containerView.addSubview(scrollView)
    containerView.addSubview(buttonStack)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
      scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
      scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

      buttonStack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
      buttonStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      buttonStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),

      scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
    ])
  }

  @objc private func copyClicked() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(textView.string, forType: .string)
  }

  @objc private func closeClicked() {
    dismiss()
  }

  private func installKeyMonitorIfNeeded() {
    guard localMonitor == nil else { return }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { // Escape
        self?.dismiss()
        return nil
      }
      return event
    }
  }

  private func removeKeyMonitor() {
    if let monitor = localMonitor {
      NSEvent.removeMonitor(monitor)
      localMonitor = nil
    }
  }
}
