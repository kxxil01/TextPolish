import AppKit
import ServiceManagement

@main
struct GrammarCorrectionMain {
  @MainActor
  static func main() {
    if runCLIModeIfRequested() {
      return
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }

  @MainActor
  private static func runCLIModeIfRequested() -> Bool {
    let args = ProcessInfo.processInfo.arguments

    if args.contains("--unregister-login-item") {
      let app = NSApplication.shared
      app.setActivationPolicy(.prohibited)
      let delegate = LoginItemUnregisterDelegate()
      app.delegate = delegate
      app.run()
      return true
    }

    return false
  }
}

@MainActor
private final class LoginItemUnregisterDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
      do {
        try SMAppService.mainApp.unregister()
        print("Unregistered Start at Login.")
      } catch {
        let message =
          (error as? LocalizedError)?.errorDescription ??
          (error as NSError).localizedDescription
        fputs("Failed to unregister: \(message)\n", stderr)
      }
      NSApp.terminate(nil)
    }
  }
}
