import AppKit
import XCTest

@testable import GrammarCorrection

/// Each app can use its own Polish style; terminals and code editors default to Minimal.
final class AppPolishStyleTests: XCTestCase {
  private let discord = "com.hnc.Discord"
  private let ghostty = "com.mitchellh.ghostty"

  func testAppsUseTheDefaultStyleUnlessTheyAreTerminalsOrEditors() {
    let settings = Settings()

    XCTAssertEqual(settings.polishStyle(forApp: nil), .natural)
    XCTAssertEqual(settings.polishStyle(forApp: discord), .natural)
    XCTAssertEqual(settings.polishStyle(forApp: ghostty), .minimal)
    XCTAssertEqual(settings.polishStyle(forApp: "com.jetbrains.intellij"), .minimal)
  }

  func testChosenStyleWinsOverBuiltInAndDefault() {
    var settings = Settings()
    settings.appPolishStyles = [ghostty: .natural, discord: .minimal]

    XCTAssertEqual(settings.polishStyle(forApp: ghostty), .natural)
    XCTAssertEqual(settings.polishStyle(forApp: discord), .minimal)
  }

  func testMinimalDefaultAppliesToEveryOtherApp() {
    var settings = Settings()
    settings.polishStyle = .minimal

    XCTAssertEqual(settings.polishStyle(forApp: discord), .minimal)
  }

  func testAppStylesRoundTripAndOlderFilesHaveNone() throws {
    var settings = Settings()
    settings.appPolishStyles = [discord: .minimal]

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    let older = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

    XCTAssertEqual(decoded.appPolishStyles, [discord: .minimal])
    XCTAssertEqual(older.appPolishStyles, [:])
  }

  @MainActor
  func testMenuSectionChoosesAndClearsTheStyleForTheTargetApp() throws {
    let delegate = try makeDelegate()

    delegate.debugShowAppPolishStyles(bundleID: discord, name: "Discord")
    XCTAssertEqual(
      delegate.debugAppPolishStyleTitles,
      ["In Discord", "✓ Default (Natural)", "Natural", "Minimal", "Shorter", "Formal", "Friendly"]
    )

    delegate.debugSelectAppPolishStyle(title: "Minimal")
    XCTAssertEqual(Settings.loadOrCreateDefault().appPolishStyles, [discord: .minimal])
    XCTAssertEqual(
      delegate.debugAppPolishStyleTitles,
      ["In Discord", "Default (Natural)", "Natural", "✓ Minimal", "Shorter", "Formal", "Friendly"]
    )

    delegate.debugSelectAppPolishStyle(title: "Default (Natural)")
    XCTAssertEqual(Settings.loadOrCreateDefault().appPolishStyles, [:])
    XCTAssertEqual(delegate.debugAppPolishStyleTitles.dropFirst().first, "✓ Default (Natural)")
  }

  @MainActor
  func testMenuSectionShowsMinimalDefaultForTerminals() throws {
    let delegate = try makeDelegate()

    delegate.debugShowAppPolishStyles(bundleID: ghostty, name: "Ghostty")

    XCTAssertEqual(delegate.debugAppPolishStyleTitles.dropFirst().first, "✓ Default (Minimal)")
  }

  @MainActor
  private func makeDelegate() throws -> AppDelegate {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()
    return delegate
  }
}
