import AppKit
import Carbon
import XCTest

@testable import GrammarCorrection

/// Optional shortcuts that Polish in one style.
final class StyleHotKeyTests: XCTestCase {
  private let formalKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey | optionKey | cmdKey))

  func testSettingsKeepStyleShortcutsAndDropUnknownStyles() throws {
    var settings = Settings()
    settings.styleHotKeys = ["formal": formalKey, "fancy": formalKey]
    settings.normalizeRuntimeValues()

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

    XCTAssertEqual(decoded.styleHotKey(for: .formal), formalKey)
    XCTAssertNil(decoded.styleHotKey(for: .natural))
    XCTAssertNil(decoded.styleHotKeys["fancy"])
    XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).styleHotKeys, [:])
  }

  func testStyleHotKeyIDsMapBackToStyles() {
    for index in Settings.PolishStyle.allCases.indices {
      XCTAssertEqual(HotKeyManager.styleIndex(forHotKeyID: HotKeyManager.styleHotKeyID(index: index)), index)
    }
    XCTAssertNil(HotKeyManager.styleIndex(forHotKeyID: HotKeyManager.HotKeyID.polish.rawValue))
    XCTAssertNil(HotKeyManager.styleIndex(forHotKeyID: HotKeyManager.HotKeyID.analyzeTone.rawValue))
  }

  func testManagerRegistersStyleShortcutsAlongsideTheMainOnes() throws {
    var registered: [Int] = []
    let manager = HotKeyManager(
      registerHandler: { id, _, _ in
        registered.append(id)
        return EventHotKeyRef(bitPattern: registered.count)!
      },
      unregisterHandler: { _ in },
      installHandler: { _ in EventHandlerRef(bitPattern: 1) }
    )
    let formalID = HotKeyManager.styleHotKeyID(index: 3)

    try manager.registerHotKeys(polish: .polishDefault, analyzeTone: .analyzeToneDefault, extras: [formalID: formalKey])

    XCTAssertEqual(registered, [HotKeyManager.HotKeyID.polish.rawValue, HotKeyManager.HotKeyID.analyzeTone.rawValue, formalID])
  }

  @MainActor
  func testAppHandlesStyleShortcutsAndIgnoresUnknownIDs() {
    let delegate = AppDelegate()
    let start = ContinuousClock.now

    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.styleHotKeyID(index: 3), now: start))
    XCTAssertFalse(delegate.debugHandleRegisteredHotKey(HotKeyManager.styleHotKeyID(index: 99), now: start + .seconds(1)))
  }

  @MainActor
  func testRecordingAndClearingAStyleShortcutSavesLive() throws {
    let viewController = try makeViewController()
    let formalIndex = try XCTUnwrap(Settings.PolishStyle.allCases.firstIndex(of: .formal))

    viewController.styleHotKeyFields[formalIndex].hotKey = formalKey
    XCTAssertEqual(Settings.loadOrCreateDefault().styleHotKey(for: .formal), formalKey)

    let clear = NSButton()
    clear.tag = formalIndex
    viewController.clearStyleHotKey(clear)
    XCTAssertNil(Settings.loadOrCreateDefault().styleHotKey(for: .formal))
    XCTAssertNil(viewController.styleHotKeyFields[formalIndex].hotKey)
  }

  @MainActor
  func testStyleShortcutCannotReuseThePolishShortcut() throws {
    let viewController = try makeViewController()
    let formalIndex = try XCTUnwrap(Settings.PolishStyle.allCases.firstIndex(of: .formal))

    viewController.styleHotKeyFields[formalIndex].hotKey = Settings.HotKey.polishDefault

    XCTAssertNil(Settings.loadOrCreateDefault().styleHotKey(for: .formal))
    XCTAssertNil(viewController.styleHotKeyFields[formalIndex].hotKey, "The field goes back to unset")
  }

  @MainActor
  private func makeViewController() throws -> SettingsWindowViewController {
    _ = NSApplication.shared
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let controller = SettingsWindowController(keychainServiceOverride: "com.textpolish.tests.style-hotkeys")
    let viewController = try XCTUnwrap(controller.viewController)
    viewController.loadSettings()
    return viewController
  }
}
