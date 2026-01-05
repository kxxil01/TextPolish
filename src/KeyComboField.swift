import AppKit
import Carbon

class KeyComboField: NSView {
    var hotKey: Settings.HotKey? {
        didSet {
            updateDisplay()
        }
    }

    public let textField = NSTextField()
    private var isRecording = false

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
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 4

        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.alignment = .center
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.stringValue = "Click to set"
        textField.textColor = .secondaryLabelColor

        addSubview(textField)
        textField.frame = bounds
        textField.autoresizingMask = [.width, .height]

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        addGestureRecognizer(clickGesture)
    }

    @objc private func handleClick(_ sender: NSClickGestureRecognizer) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        textField.stringValue = "Press keys..."
        textField.textColor = .systemBlue
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1).cgColor

        // Capture key events
        NSEvent.addLocalMonitorForEvents(matching: NSEvent.EventTypeMask.keyDown) { [weak self] event in
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
        isRecording = false
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        updateDisplay()
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

    func loadFromHotKey(_ hotKey: Settings.HotKey) {
        self.hotKey = hotKey
    }
}
