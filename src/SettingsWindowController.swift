import AppKit

class SettingsWindowController: NSWindowController {
    var viewController: SettingsWindowViewController?

    convenience init() {
        let window = Self.createWindow()
        self.init(window: window)
        self.window?.title = "TextPolish Settings"
        self.window?.isReleasedWhenClosed = false
        self.window?.delegate = self

        setupViewController()
    }

    private static func createWindow() -> NSWindow {
        let size = NSSize(width: 560, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.level = .floating
        window.minSize = size
        window.maxSize = size
        window.collectionBehavior = [.transient, .stationary]
        return window
    }

    private func setupViewController() {
        let vc = SettingsWindowViewController()
        viewController = vc
        vc.settingsWindowController = self

        _ = vc.view
        window?.contentView = vc.view
    }

    override func close() {
        window?.close()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        // Settings are saved live; nothing to do on close.
    }
}
