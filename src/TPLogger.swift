import Foundation
import os

enum TPLogger {
  private static let testPrefix = "[TextPolishTest]"
  private static let productionPrefix = "[TextPolish]"
  private static let logger = Logger(subsystem: "com.kxxil01.TextPolish", category: "app")

  static var isRunningTests: Bool {
    NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  /// Writes a public line to the system log. NSLog text shows up as `<private>`, which made these
  /// lines unreadable, so callers must never pass the user's text or a secret.
  /// Test runs write to stderr instead, so they show in the test output and stay out of the app's system log.
  static func log(_ message: @autoclosure () -> String) {
    if isRunningTests {
      FileHandle.standardError.write(Data("\(testPrefix) \(message())\n".utf8))
      return
    }
    let line = "\(productionPrefix) \(message())"
    logger.log("\(line, privacy: .public)")
  }
}
