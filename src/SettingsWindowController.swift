import AppKit

class SettingsWindowController: NSWindowController {
    var viewController: SettingsWindowViewController?

    /// A bare `SettingsWindowController()` would otherwise resolve to NSWindowController's inherited
    /// `init()`, which builds no window, so Settings silently never opens. Block it at compile time.
    @available(*, unavailable, message: "Use init(keychainServiceOverride:) and pass nil for the app keychain")
    convenience init() {
        self.init(window: nil)
    }

    convenience init(keychainServiceOverride: String?) {
        let window = Self.createWindow()
        self.init(window: window)
        self.window?.title = "TextPolish Settings"
        self.window?.isReleasedWhenClosed = false
        self.window?.delegate = self

        setupViewController(keychainServiceOverride: keychainServiceOverride)
    }

    private static func createWindow() -> NSWindow {
        let size = NSSize(width: 560, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.center()
        window.level = .floating
        window.minSize = size
        window.maxSize = size
        window.collectionBehavior = [.transient, .stationary]
        return window
    }

    func setupViewController(keychainServiceOverride: String? = nil) {
        guard viewController == nil else { return }
        let controller = SettingsWindowViewController()
        controller.keychainServiceOverride = keychainServiceOverride
        viewController = controller
        controller.settingsWindowController = self

        _ = controller.view
        window?.contentView = controller.view
        controller.fitWindowToSection(animated: false)
        window?.center()
    }

    override func close() {
        window?.close()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        // Settings save live on end-editing, so finish any edit still in progress.
        viewController?.commitPendingEdits()
    }
}
