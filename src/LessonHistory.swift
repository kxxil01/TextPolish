import Foundation

/// One Learn mode explanation, kept so it can be reviewed after its panel closes.
struct Lesson: Codable, Equatable, Sendable {
  let date: Date
  let lines: [String]
}

/// A change Learn mode explained more than once, so the writer can watch for it.
struct RepeatedMistake: Codable, Equatable, Sendable {
  let before: String
  let after: String
  var reason: String?
  var count: Int
  var lastSeen: Date

  /// "needsed → needed: spelling (3 times)", in the form the Learn panel colors.
  var line: String {
    let reasonText = reason.map { ": \($0)" } ?? ""
    return "\(before) → \(after)\(reasonText) (\(count) times)"
  }

  /// Reads "before → after: reason". Nil for a line without an arrow.
  init?(line: String, at date: Date) {
    guard let arrow = line.range(of: "→") else { return nil }
    let afterAndReason = line[arrow.upperBound...]
    let reasonSplit = afterAndReason.range(of: ": ")
    before = Self.phrase(line[..<arrow.lowerBound])
    after = Self.phrase(reasonSplit.map { afterAndReason[..<$0.lowerBound] } ?? afterAndReason)
    reason = reasonSplit.map { String(afterAndReason[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
    count = 1
    lastSeen = date
    guard !before.isEmpty, !after.isEmpty else { return nil }
  }

  /// The same change in any capitalization or quoting counts as one mistake.
  var key: String {
    "\(before.lowercased())→\(after.lowercased())"
  }

  private static func phrase(_ text: Substring) -> String {
    text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’")))
  }
}

/// The most recent Learn mode explanations, newest first, saved next to the settings file on this Mac only.
/// It also counts each explained change across all lessons, so repeated mistakes stand out.
@MainActor
final class LessonHistory {
  static let maxLessons = 20
  static let maxTrackedMistakes = 200

  private(set) var lessons: [Lesson] = []
  private var mistakes: [String: RepeatedMistake] = [:]
  private var progress = WeeklyProgress()
  private let fileURL: URL
  private let mistakesFileURL: URL
  private let progressFileURL: URL

  init(fileURL: URL = LessonHistory.defaultFileURL) {
    self.fileURL = fileURL
    let name = fileURL.deletingPathExtension().lastPathComponent + "-mistakes.json"
    mistakesFileURL = fileURL.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false)
    let progressName = fileURL.deletingPathExtension().lastPathComponent + "-weeks.json"
    progressFileURL = fileURL.deletingLastPathComponent().appendingPathComponent(progressName, isDirectory: false)
    if let data = try? Data(contentsOf: fileURL),
       let saved = try? JSONDecoder().decode([Lesson].self, from: data)
    {
      lessons = Array(saved.prefix(Self.maxLessons))
    }
    if let data = try? Data(contentsOf: mistakesFileURL),
       let saved = try? JSONDecoder().decode([String: RepeatedMistake].self, from: data)
    {
      mistakes = saved
    }
    if let data = try? Data(contentsOf: progressFileURL),
       let saved = try? JSONDecoder().decode(WeeklyProgress.self, from: data)
    {
      progress = saved
    }
  }

  /// This week's progress for Recent Lessons; empty until Learn has explained something this week.
  func progressSummary(now: Date = Date()) -> [String] {
    progress.summary(now: now)
  }

  /// Changes explained at least twice, most frequent first, then most recent.
  func repeatedMistakes(limit: Int = 5) -> [RepeatedMistake] {
    let repeated = mistakes.values.filter { $0.count >= 2 }
    return Array(repeated.sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }.prefix(limit))
  }

  nonisolated static var defaultFileURL: URL {
    Settings.settingsFileURL().deletingLastPathComponent().appendingPathComponent("lessons.json", isDirectory: false)
  }

  func add(_ lines: [String], at date: Date = Date()) {
    guard !lines.isEmpty else { return }
    lessons.insert(Lesson(date: date, lines: lines), at: 0)
    lessons = Array(lessons.prefix(Self.maxLessons))
    countMistakes(in: lines, at: date)
    progress.record(lines.compactMap { RepeatedMistake(line: $0, at: date) }, at: date)
    save()
  }

  func clear() {
    lessons = []
    mistakes = [:]
    progress = WeeklyProgress()
    try? FileManager.default.removeItem(at: fileURL)
    try? FileManager.default.removeItem(at: mistakesFileURL)
    try? FileManager.default.removeItem(at: progressFileURL)
  }

  private func countMistakes(in lines: [String], at date: Date) {
    for mistake in lines.compactMap({ RepeatedMistake(line: $0, at: date) }) {
      if var known = mistakes[mistake.key] {
        known.count += 1
        known.lastSeen = date
        known.reason = mistake.reason ?? known.reason
        mistakes[mistake.key] = known
      } else {
        mistakes[mistake.key] = mistake
      }
    }
    // Forget the changes seen longest ago once the list is full.
    if mistakes.count > Self.maxTrackedMistakes {
      let oldest = mistakes.sorted { $0.value.lastSeen < $1.value.lastSeen }.prefix(mistakes.count - Self.maxTrackedMistakes)
      oldest.forEach { mistakes[$0.key] = nil }
    }
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(lessons).write(to: fileURL, options: .atomic)
      try JSONEncoder().encode(mistakes).write(to: mistakesFileURL, options: .atomic)
      try JSONEncoder().encode(progress).write(to: progressFileURL, options: .atomic)
    } catch {
      TPLogger.log("Could not save lessons: \(error.localizedDescription)")
    }
  }
}
