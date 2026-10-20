import XCTest
import Carbon

@testable import GrammarCorrection

final class HotKeyManagerTests: XCTestCase {
  func testRegisterHotKeysRestoresFailedHotKeyAndKeepsSuccessfulUpdates() {
    struct RegisterCall: Equatable {
      let id: Int
      let keyCode: UInt32
      let modifiers: UInt32
    }

    var calls: [RegisterCall] = []
    var active: [Int: Settings.HotKey] = [:]
    var failToneKeyCode: UInt32?

    let registerHandler: HotKeyManager.RegisterHandler = { id, keyCode, modifiers in
      calls.append(RegisterCall(id: id, keyCode: keyCode, modifiers: modifiers))
      if id == HotKeyManager.HotKeyID.analyzeTone.rawValue, keyCode == failToneKeyCode {
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

    let oldPolish = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
    let oldAnalyzeTone = Settings.HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey))

    XCTAssertNoThrow(try manager.registerHotKeys(polish: oldPolish, analyzeTone: oldAnalyzeTone))
    XCTAssertEqual(active[HotKeyManager.HotKeyID.polish.rawValue], oldPolish)
    XCTAssertEqual(active[HotKeyManager.HotKeyID.analyzeTone.rawValue], oldAnalyzeTone)

    let newPolish = Settings.HotKey(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey))
    let newAnalyzeTone = Settings.HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey))
    failToneKeyCode = newAnalyzeTone.keyCode

    XCTAssertThrowsError(try manager.registerHotKeys(polish: newPolish, analyzeTone: newAnalyzeTone))
    XCTAssertEqual(active[HotKeyManager.HotKeyID.polish.rawValue], newPolish)
    XCTAssertEqual(active[HotKeyManager.HotKeyID.analyzeTone.rawValue], oldAnalyzeTone)
  }

  func testRegisterHotKeysKeepsAvailableHotKeysWhenOneIsUnavailable() {
    var active: [Int: Settings.HotKey] = [:]

    let registerHandler: HotKeyManager.RegisterHandler = { id, keyCode, modifiers in
      if id == HotKeyManager.HotKeyID.analyzeTone.rawValue {
        throw HotKeyManager.HotKeyManagerError.alreadyInUse
      }
      let hotKey = Settings.HotKey(keyCode: keyCode, modifiers: modifiers)
      active[id] = hotKey
      return EventHotKeyRef(bitPattern: id + 1)!
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

    XCTAssertThrowsError(
      try manager.registerHotKeys(
        polish: Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey)),
        analyzeTone: Settings.HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey))
      )
    )

    XCTAssertNotNil(active[HotKeyManager.HotKeyID.polish.rawValue])
    XCTAssertNil(active[HotKeyManager.HotKeyID.analyzeTone.rawValue])
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
