import Foundation
import OSLog

/// TextPolish's own log lines since launch, for pasting into a bug report. They never contain the user's text.
enum RecentLogs {
  static let maxLines = 300
  static let appSubsystem = "com.kxxil01.TextPolish"

  /// Reads the log store, which can take a moment, so call it off the main thread.
  static func text(subsystem: String = appSubsystem) -> String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build"
    let header = "TextPolish \(version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    do {
      let store = try OSLogStore(scope: .currentProcessIdentifier)
      let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", subsystem))
      let formatter = DateFormatter()
      formatter.dateFormat = "HH:mm:ss.SSS"
      let lines = entries
        .compactMap { $0 as? OSLogEntryLog }
        .map { "\(formatter.string(from: $0.date)) \($0.composedMessage)" }
      guard !lines.isEmpty else {
        return header + "\nNo log lines since TextPolish started."
      }
      return ([header] + lines.suffix(maxLines)).joined(separator: "\n")
    } catch {
      return header + "\nCould not read logs: \(error.localizedDescription)"
    }
  }
}
