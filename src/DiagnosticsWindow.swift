import AppKit

@MainActor
final class DiagnosticsWindow: NSPanel, NSWindowDelegate {
  private let textView = NSTextView()
  private let runButton = NSButton(title: "Run Diagnostic", target: nil, action: nil)
  private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
  private let closeButton = NSButton(title: "Close", target: nil, action: nil)
  private let spinner = NSProgressIndicator()
  private var localMonitor: Any?

  var onRunDiagnostic: (() -> Void)?

  init() {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
      styleMask: [.titled, .closable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    setupWindow()
    setupUI()
  }

  func update(with snapshot: DiagnosticsSnapshot?) {
    // Only update if not currently running a diagnostic
    if !spinner.isHidden { return }
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

  func showRunning() {
    runButton.isEnabled = false
    spinner.isHidden = false
    spinner.startAnimation(nil)
    textView.string = "Running diagnostic…"
  }

  func showResult(_ text: String) {
    spinner.stopAnimation(nil)
    spinner.isHidden = true
    runButton.isEnabled = true
    textView.string = text
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

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isHidden = true
    spinner.translatesAutoresizingMaskIntoConstraints = false

    runButton.target = self
    runButton.action = #selector(runClicked)
    runButton.bezelStyle = .rounded

    copyButton.target = self
    copyButton.action = #selector(copyClicked)
    copyButton.bezelStyle = .rounded

    closeButton.target = self
    closeButton.action = #selector(closeClicked)
    closeButton.keyEquivalent = "\r"
    closeButton.bezelStyle = .rounded

    let buttonStack = NSStackView(views: [runButton, spinner, copyButton, closeButton])
    buttonStack.orientation = .horizontal
    buttonStack.alignment = .centerY
    buttonStack.spacing = 8
    buttonStack.translatesAutoresizingMaskIntoConstraints = false

    containerView.addSubview(scrollView)
    containerView.addSubview(buttonStack)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
      scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
      scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

      buttonStack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 12),
      buttonStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
      buttonStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),

      scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
    ])
  }

  @objc private func runClicked() {
    onRunDiagnostic?()
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
