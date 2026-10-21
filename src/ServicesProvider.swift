import AppKit

/// Right-click > Services > "Polish with TextPolish" or "Translate to English with TextPolish".
/// macOS hands over the selected text; the result is pasted over the selection, as with a shortcut.
/// The entries are declared under `NSServices` in the app's Info.plist (scripts/build_app.sh).
@MainActor
final class ServicesProvider: NSObject {
  enum Action: Equatable, Sendable {
    case polish
    case translate
  }

  private let onRequest: @MainActor (Action, String) -> Void

  init(onRequest: @escaping @MainActor (Action, String) -> Void) {
    self.onRequest = onRequest
  }

  @objc func polishService(
    _ pasteboard: NSPasteboard,
    userData _: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    handle(.polish, pasteboard: pasteboard, error: error)
  }

  @objc func translateService(
    _ pasteboard: NSPasteboard,
    userData _: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    handle(.translate, pasteboard: pasteboard, error: error)
  }

  private func handle(_ action: Action, pasteboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      error.pointee = "No text selected" as NSString
      return
    }
    TPLogger.log("Service: \(action) chars=\(text.count)")
    onRequest(action, text)
  }
}
