import Foundation

enum TPLogger {
  private static let testPrefix = "[TextPolishTest]"
  private static let productionPrefix = "[TextPolish]"

  static var isRunningTests: Bool {
    NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  }

  static func log(_ message: @autoclosure () -> String) {
    let prefix = isRunningTests ? testPrefix : productionPrefix
    NSLog("\(prefix) \(message())")
  }
}
