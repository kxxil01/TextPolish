import AppKit
import Carbon
import Foundation

enum StatusItemCountFormatter {
  static func title(for count: Int) -> String {
    guard count > 0 else { return "" }
    if count > 99 {
      return " 99+"
    }
    return " \(count)"
  }
}

enum DailyResetScheduler {
  static func nextResetDate(after now: Date, calendar: Calendar = .current) -> Date {
    calendar.nextDate(
      after: now,
      matching: DateComponents(hour: 0, minute: 0, second: 0),
      matchingPolicy: .nextTime,
      repeatedTimePolicy: .first,
      direction: .forward
    ) ?? now.addingTimeInterval(3600)
  }
}

struct HotKeyPressDebouncer {
  private var lastAcceptedByID: [Int: ContinuousClock.Instant] = [:]
  let cooldown: Duration

  init(cooldown: Duration) {
    self.cooldown = cooldown
  }

  mutating func shouldAccept(id: Int, now: ContinuousClock.Instant) -> Bool {
    if let lastAccepted = lastAcceptedByID[id], now < lastAccepted + cooldown {
      return false
    }
    lastAcceptedByID[id] = now
    return true
  }
}

enum EscapeKeyCancellationMatcher {
  static func shouldCancel(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags
  ) -> Bool {
    let relevantModifiers = modifiers.intersection([.command, .control, .option, .shift])
    return keyCode == UInt16(kVK_Escape) && relevantModifiers.isEmpty
  }
}

enum HotKeyPromptDecision: Equatable {
  case passThrough
  case cancel
  case reset
  case missingModifier
  case capture(Settings.HotKey)
}

enum HotKeyPromptInterpreter {
  static func interpret(
    eventType: NSEvent.EventType,
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags
  ) -> HotKeyPromptDecision {
    let relevantModifiers = modifiers.intersection([.command, .control, .option, .shift])
    if eventType == .flagsChanged {
      return .passThrough
    }

    if keyCode == UInt16(kVK_Escape), relevantModifiers.isEmpty {
      return .cancel
    }

    if keyCode == UInt16(kVK_Tab), relevantModifiers.isEmpty {
      return .reset
    }

    if relevantModifiers.isEmpty {
      return .missingModifier
    }

    var carbonModifiers: UInt32 = 0
    if relevantModifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
    if relevantModifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
    if relevantModifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
    if relevantModifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

    return .capture(Settings.HotKey(keyCode: UInt32(keyCode), modifiers: carbonModifiers))
  }
}
