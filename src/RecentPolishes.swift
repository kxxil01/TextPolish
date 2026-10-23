import Foundation

/// One Polish the writer kept: what they wrote and what was pasted.
struct RecentPolish: Codable, Equatable, Sendable {
  let date: Date
  let appName: String
  let styleName: String
  let original: String
  let polished: String
}

/// The last Polishes, newest first, saved next to the settings file on this Mac only and only while the writer has
/// Recent Polishes turned on, so text from before the last Undo can be found again.
@MainActor
final class RecentPolishes {
  static let maxEntries = 20

  private(set) var entries: [RecentPolish] = []
  private let fileURL: URL

  init(fileURL: URL = RecentPolishes.defaultFileURL) {
    self.fileURL = fileURL
    if let data = try? Data(contentsOf: fileURL),
       let saved = try? JSONDecoder().decode([RecentPolish].self, from: data)
    {
      entries = Array(saved.prefix(Self.maxEntries))
    }
  }

  nonisolated static var defaultFileURL: URL {
    Settings.settingsFileURL().deletingLastPathComponent().appendingPathComponent("recent-polishes.json", isDirectory: false)
  }

  func add(_ entry: RecentPolish) {
    entries.insert(entry, at: 0)
    entries = Array(entries.prefix(Self.maxEntries))
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
      // The writer's text: readable by them only, like the settings file.
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    } catch {
      TPLogger.log("Could not save recent polishes: \(error.localizedDescription)")
    }
  }

  func clear() {
    entries = []
    try? FileManager.default.removeItem(at: fileURL)
  }
}
