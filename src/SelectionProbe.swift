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

  /// Full text of the focused field, or nil when Accessibility cannot read it.
  static func focusedValue(forProcess pid: pid_t) -> String? {
    focusedElement(forProcess: pid).flatMap { stringAttribute(kAXValueAttribute, of: $0) }
  }

  static func focusedSelectedText(forProcess pid: pid_t) -> String? {
    focusedElement(forProcess: pid).flatMap { stringAttribute(kAXSelectedTextAttribute, of: $0) }
  }

  /// Selects a range (in UTF-16 units, as Accessibility counts) of the focused field; false when the app refuses.
  static func selectFocusedRange(_ range: NSRange, forProcess pid: pid_t) -> Bool {
    guard let element = focusedElement(forProcess: pid) else { return false }
    var axRange = CFRange(location: range.location, length: range.length)
    guard let value = AXValueCreate(.cfRange, &axRange) else { return false }
    return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
  }

  private static func focusedElement(forProcess pid: pid_t) -> AXUIElement? {
    elementAttribute(kAXFocusedUIElementAttribute, of: AXUIElementCreateApplication(pid))
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
