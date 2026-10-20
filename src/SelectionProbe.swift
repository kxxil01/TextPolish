import ApplicationServices
import Foundation

/// What the focused text field reports about its selection.
enum SelectionState: Equatable, Sendable {
  /// The field has selected text.
  case selected
  /// The field has text but nothing is selected.
  case nothingSelected
  /// Accessibility could not tell: unsupported app, no focused field, or an empty field.
  case unknown
}

enum SelectionProbe {
  /// Reads the focused element of `pid` (or the system-wide focus) through Accessibility.
  static func state(forProcess pid: pid_t?) -> SelectionState {
    let root = pid.map(AXUIElementCreateApplication) ?? AXUIElementCreateSystemWide()
    guard let focused = elementAttribute(kAXFocusedUIElementAttribute, of: root),
          let selected = stringAttribute(kAXSelectedTextAttribute, of: focused)
    else {
      return .unknown
    }
    if !selected.isEmpty {
      return .selected
    }
    // An empty selection only means "use the whole field" when the field has text to select.
    guard let value = stringAttribute(kAXValueAttribute, of: focused), !value.isEmpty else {
      return .unknown
    }
    return .nothingSelected
  }

  private static func elementAttribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return unsafeBitCast(value, to: AXUIElement.self)
  }

  private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }
}
