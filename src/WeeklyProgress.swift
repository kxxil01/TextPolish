import Foundation

/// Messages and explained changes per week, so Recent Lessons can show whether mistakes are getting rarer.
struct WeeklyProgress: Codable, Equatable, Sendable {
  struct Week: Codable, Equatable, Sendable {
    var messages = 0
    var changes = 0
    /// "before → after", then how often Learn explained it that week.
    var mistakes: [String: Int] = [:]
  }

  static let weeksKept = 8

  private(set) var weeks: [String: Week] = [:]

  /// One Polish that Learn explained, with the changes it explained.
  mutating func record(_ changes: [RepeatedMistake], at date: Date) {
    let key = Self.weekKey(date)
    var week = weeks[key, default: Week()]
    week.messages += 1
    week.changes += changes.count
    for change in changes {
      week.mistakes["\(change.before) → \(change.after)", default: 0] += 1
    }
    weeks[key] = week
    for old in weeks.keys.sorted().dropLast(Self.weeksKept) {
      weeks[old] = nil
    }
  }

  /// This week's messages and changes per message, compared with last week, then the most repeated change.
  func summary(now: Date = Date()) -> [String] {
    guard let week = weeks[Self.weekKey(now)], week.messages > 0 else { return [] }
    let average = Double(week.changes) / Double(week.messages)
    var lines = ["\(week.messages) \(week.messages == 1 ? "message" : "messages") explained, \(Self.format(average)) changes each"]
    let lastWeekDate = Calendar(identifier: .iso8601).date(byAdding: .day, value: -7, to: now) ?? now
    if let lastWeek = weeks[Self.weekKey(lastWeekDate)], lastWeek.messages > 0 {
      let lastAverage = Double(lastWeek.changes) / Double(lastWeek.messages)
      if average < lastAverage - 0.05 {
        lines.append("Down from \(Self.format(lastAverage)) last week. Nice work.")
      } else if average > lastAverage + 0.05 {
        lines.append("Up from \(Self.format(lastAverage)) last week.")
      } else {
        lines.append("About the same as last week.")
      }
    }
    let repeated = week.mistakes.filter { $0.value >= 2 }.max { ($0.value, $1.key) < ($1.value, $0.key) }
    if let repeated {
      lines.append("Most repeated: \(repeated.key) (\(repeated.value) times)")
    }
    return lines
  }

  /// The ISO week a date falls in, such as "2026-W43".
  static func weekKey(_ date: Date) -> String {
    let calendar = Calendar(identifier: .iso8601)
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.1f", value)
  }
}
