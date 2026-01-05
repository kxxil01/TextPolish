import AppKit

class SettingsWindowController: NSWindowController {
    var viewController: SettingsWindowViewController?

    convenience init() {
        self.init(window: Self.createWindow())
        self.window?.title = "TextPolish Settings"
        self.window?.isReleasedWhenClosed = false
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

    override func windowDidLoad() {
        super.windowDidLoad()
        setupViewController()
    }

    private func setupViewController() {
        let vc = SettingsWindowViewController()
        viewController = vc
        vc.settingsWindowController = self

        window?.contentView = vc.view
        vc.view.frame = NSRect(x: 0, y: 0, width: 600, height: 450)
        vc.view.autoresizingMask = [.width, .height]
    }

    override func close() {
        window?.close()
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let settings = viewController?.settings {
            do {
                try Settings.save(settings)
                NotificationCenter.default.post(name: .settingsDidChange, object: settings)
            } catch {
                print("Failed to save settings: \(error)")
            }
        }
    }
}
