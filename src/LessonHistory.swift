import Foundation

/// One Learn mode explanation, kept so it can be reviewed after its panel closes.
struct Lesson: Codable, Equatable, Sendable {
  let date: Date
  let lines: [String]
}

/// The most recent Learn mode explanations, newest first, saved next to the settings file on this Mac only.
@MainActor
final class LessonHistory {
  static let maxLessons = 20

  private(set) var lessons: [Lesson] = []
  private let fileURL: URL

  init(fileURL: URL = LessonHistory.defaultFileURL) {
    self.fileURL = fileURL
    if let data = try? Data(contentsOf: fileURL),
       let saved = try? JSONDecoder().decode([Lesson].self, from: data)
    {
      lessons = Array(saved.prefix(Self.maxLessons))
    }
  }

  nonisolated static var defaultFileURL: URL {
    Settings.settingsFileURL().deletingLastPathComponent().appendingPathComponent("lessons.json", isDirectory: false)
  }

  func add(_ lines: [String], at date: Date = Date()) {
    guard !lines.isEmpty else { return }
    lessons.insert(Lesson(date: date, lines: lines), at: 0)
    lessons = Array(lessons.prefix(Self.maxLessons))
    save()
  }

  func clear() {
    lessons = []
    try? FileManager.default.removeItem(at: fileURL)
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(lessons).write(to: fileURL, options: .atomic)
    } catch {
      TPLogger.log("Could not save lessons: \(error.localizedDescription)")
    }
  }
}
