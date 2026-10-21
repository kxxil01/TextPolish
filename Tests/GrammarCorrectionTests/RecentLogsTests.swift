import os
import XCTest

@testable import GrammarCorrection

/// Diagnostics > Copy Logs reads this process's log lines for the app's subsystem.
final class RecentLogsTests: XCTestCase {
  func testReadsLinesForTheSubsystemWithAHeader() {
    let subsystem = "com.kxxil01.TextPolish.tests.\(UUID().uuidString)"
    let marker = "recent-logs-\(UUID().uuidString)"
    Logger(subsystem: subsystem, category: "test").log("\(marker, privacy: .public)")

    let text = RecentLogs.text(subsystem: subsystem)

    XCTAssertTrue(text.hasPrefix("TextPolish "), text)
    XCTAssertTrue(text.contains("macOS"), text)
    XCTAssertTrue(text.contains(marker), text)
  }

  func testOtherSubsystemsAreLeftOut() {
    let marker = "other-subsystem-\(UUID().uuidString)"
    Logger(subsystem: "com.example.other", category: "test").log("\(marker, privacy: .public)")

    let text = RecentLogs.text(subsystem: "com.kxxil01.TextPolish.tests.\(UUID().uuidString)")

    XCTAssertFalse(text.contains(marker))
    XCTAssertTrue(text.hasSuffix("No log lines since TextPolish started."), text)
  }
}
