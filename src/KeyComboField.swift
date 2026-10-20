import AppKit
import Carbon

class KeyComboField: NSView {
    var hotKey: Settings.HotKey? {
        didSet {
            updateDisplay()
            onChange?(hotKey)
        }
    }

    /// Called when the user captures a new hotkey. Set by the settings view controller for live save.
    var onChange: ((Settings.HotKey?) -> Void)?

    public let textField = NSTextField()
    private var isRecording = false
    private var keyDownMonitor: Any?

    /// Only one field records at a time; starting another stops the previous one.
    private static weak var activeRecorder: KeyComboField?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = "Click to set"
        textField.textColor = .secondaryLabelColor

        addSubview(textField)
        centerTextField()
        applyColors()

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        addGestureRecognizer(clickGesture)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        centerTextField()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func accessibilityPerformPress() -> Bool {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
        return true
    }

    /// Labels draw from the top, so center a single text line vertically inside the field.
    private func centerTextField() {
        let lineHeight = ceil(textField.intrinsicContentSize.height)
        textField.frame = NSRect(
            x: 4,
            y: (bounds.height - lineHeight) / 2,
            width: max(0, bounds.width - 8),
            height: lineHeight
        )
    }

    /// Layer colors are fixed CGColors, so resolve them for the current appearance.
    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let background = isRecording
                ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                : NSColor.controlBackgroundColor
            let border = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
            layer?.backgroundColor = background.cgColor
            layer?.borderColor = border.cgColor
        }
    }

    @objc private func handleClick(_ sender: NSClickGestureRecognizer) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        if let other = Self.activeRecorder, other !== self {
            other.stopRecording()
        }
        Self.activeRecorder = self
        removeKeyMonitorIfNeeded()
        isRecording = true
        textField.stringValue = "Type shortcut, Esc to cancel"
        textField.textColor = .controlAccentColor
        applyColors()

        // Capture key events
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            if event.keyCode == 53 { // Escape key
                self.stopRecording()
                return nil
            }

            self.handleKeyEvent(event)
            return nil
        }
    }

    private func stopRecording() {
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
        isRecording = false
        removeKeyMonitorIfNeeded()
        applyColors()
        updateDisplay()
    }

    private func removeKeyMonitorIfNeeded() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        var modifiers: UInt32 = 0

        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }

        hotKey = Settings.HotKey(keyCode: keyCode, modifiers: modifiers)
        stopRecording()
    }

    private func updateDisplay() {
        guard let hotKey = hotKey else {
            textField.stringValue = "Click to set"
            textField.textColor = .secondaryLabelColor
            return
        }

        textField.stringValue = hotKey.displayString
        textField.textColor = .labelColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Leaving the window (tab switch, window close) must not leave a key monitor running.
        if window == nil, isRecording {
            stopRecording()
        }
    }

    var hasActiveKeyDownMonitor: Bool {
        keyDownMonitor != nil
    }

    func loadFromHotKey(_ hotKey: Settings.HotKey) {
        let savedCallback = onChange
        onChange = nil
        self.hotKey = hotKey
        onChange = savedCallback
    }

    deinit {
        removeKeyMonitorIfNeeded()
    }
}
