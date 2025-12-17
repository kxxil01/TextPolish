@preconcurrency import ApplicationServices
@preconcurrency import Carbon

final class KeyboardController {
  func isAccessibilityTrusted(prompt: Bool) -> Bool {
    if prompt {
      let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
      return AXIsProcessTrustedWithOptions(options)
    }
    return AXIsProcessTrusted()
  }

  func sendCommandC() {
    post(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
  }

  func sendCommandV() {
    post(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
  }

  func sendCommandA() {
    post(keyCode: CGKeyCode(kVK_ANSI_A), flags: .maskCommand)
  }

  private func post(keyCode: CGKeyCode, flags: CGEventFlags) {
    guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = flags
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = flags

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }
}
