import XCTest
import Carbon

@testable import GrammarCorrection

final class HotKeyManagerTests: XCTestCase {
  func testRegisterHotKeysRestoresPreviousOnFailure() {
    struct RegisterCall: Equatable {
      let id: Int
      let keyCode: UInt32
      let modifiers: UInt32
    }

    var calls: [RegisterCall] = []
    var active: [Int: Settings.HotKey] = [:]
    var failAllKeyCode: UInt32?

    let registerHandler: HotKeyManager.RegisterHandler = { id, keyCode, modifiers in
      calls.append(RegisterCall(id: id, keyCode: keyCode, modifiers: modifiers))
      if id == HotKeyManager.HotKeyID.correctAll.rawValue, keyCode == failAllKeyCode {
        throw HotKeyManager.HotKeyManagerError.couldNotRegisterHotKey(-1)
      }
      active[id] = Settings.HotKey(keyCode: keyCode, modifiers: modifiers)
      return EventHotKeyRef(bitPattern: calls.count + 1)!
    }

    let unregisterHandler: HotKeyManager.UnregisterHandler = { _ in
      active.removeAll()
    }

    let installHandler: HotKeyManager.InstallHandler = { _ in
      EventHandlerRef(bitPattern: 1)
    }

    let manager = HotKeyManager(
      registerHandler: registerHandler,
      unregisterHandler: unregisterHandler,
      installHandler: installHandler
    )

    let oldSelection = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
    let oldAll = Settings.HotKey(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey))
    let oldAnalyzeTone = Settings.HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey))

    XCTAssertNoThrow(try manager.registerHotKeys(correctSelection: oldSelection, correctAll: oldAll, analyzeTone: oldAnalyzeTone))
    XCTAssertEqual(active[HotKeyManager.HotKeyID.correctSelection.rawValue], oldSelection)
    XCTAssertEqual(active[HotKeyManager.HotKeyID.correctAll.rawValue], oldAll)
    XCTAssertEqual(active[HotKeyManager.HotKeyID.analyzeTone.rawValue], oldAnalyzeTone)

    let newSelection = Settings.HotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey))
    let newAll = Settings.HotKey(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey))
    let newAnalyzeTone = Settings.HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey))
    failAllKeyCode = newAll.keyCode

    XCTAssertThrowsError(try manager.registerHotKeys(correctSelection: newSelection, correctAll: newAll, analyzeTone: newAnalyzeTone))
    XCTAssertEqual(active[HotKeyManager.HotKeyID.correctSelection.rawValue], oldSelection)
    XCTAssertEqual(active[HotKeyManager.HotKeyID.correctAll.rawValue], oldAll)
    XCTAssertEqual(active[HotKeyManager.HotKeyID.analyzeTone.rawValue], oldAnalyzeTone)
  }

  func testIsHotKeyInUseIgnoresCurrentHotKeys() {
    let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
    var checkerCalled = false

    let inUse = HotKeyManager.isHotKeyInUse(
      hotKey: hotKey,
      ignoring: [hotKey],
      checker: { _, _ in
        checkerCalled = true
        return true
      }
    )

    XCTAssertFalse(inUse)
    XCTAssertFalse(checkerCalled)
  }

  func testIsHotKeyInUseUsesCheckerWhenNotIgnored() {
    let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
    var checkerCalled = false

    let inUse = HotKeyManager.isHotKeyInUse(
      hotKey: hotKey,
      ignoring: [],
      checker: { _, _ in
        checkerCalled = true
        return true
      }
    )

    XCTAssertTrue(inUse)
    XCTAssertTrue(checkerCalled)
  }
}
