import AppKit

class SettingsWindowController: NSWindowController {
    var viewController: SettingsWindowViewController?

    convenience init() {
        let window = Self.createWindow()
        self.init(window: window)
        self.window?.title = "TextPolish Settings"
        self.window?.isReleasedWhenClosed = false
        self.window?.delegate = self

        // Set up view controller immediately when window is created
        setupViewController()
    }

    private static func createWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.level = .floating  // Stay on top
        window.minSize = NSSize(width: 600, height: 450)
        window.maxSize = NSSize(width: 800, height: 800)
        window.collectionBehavior = [.transient, .stationary]  // Don't appear in Spaces
        return window
    }

    private func setupViewController() {
        let vc = SettingsWindowViewController()
        viewController = vc
        vc.settingsWindowController = self

        // Force the view to load by accessing it
        let _ = vc.view

        window?.contentView = vc.view
    }

    override func close() {
        window?.close()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Settings are persisted via Apply (saveAndNotify); closing behaves like cancel.
    }
}
