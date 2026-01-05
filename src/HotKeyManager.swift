import Carbon
import AppKit

final class HotKeyManager {
  typealias RegisterHandler = (_ id: Int, _ keyCode: UInt32, _ modifiers: UInt32) throws -> EventHotKeyRef
  typealias UnregisterHandler = (_ ref: EventHotKeyRef) -> Void
  typealias InstallHandler = (_ manager: HotKeyManager) throws -> EventHandlerRef?

  enum HotKeyID: Int {
    case correctSelection = 1
    case correctAll = 2
    case analyzeTone = 3
  }

  enum HotKeyManagerError: Error {
    case couldNotInstallHandler(OSStatus)
    case couldNotRegisterHotKey(OSStatus)
    case alreadyInUse
  }

  var onHotKey: ((Int) -> Void)?

  private var handlerRef: EventHandlerRef?
  private var hotKeyRefs: [Int: EventHotKeyRef] = [:]
  private var registeredSelection: Settings.HotKey?
  private var registeredAll: Settings.HotKey?
  private var registeredAnalyzeTone: Settings.HotKey?

  private static let signature: OSType = 0x47434F52 // 'GCOR'
  private static let eventHotKeyDuplicateErr: OSStatus = -9962
  private let registerHandler: RegisterHandler
  private let unregisterHandler: UnregisterHandler
  private let installHandler: InstallHandler

  init(
    registerHandler: @escaping RegisterHandler = HotKeyManager.defaultRegisterHandler,
    unregisterHandler: @escaping UnregisterHandler = HotKeyManager.defaultUnregisterHandler,
    installHandler: @escaping InstallHandler = HotKeyManager.defaultInstallHandler
  ) {
    self.registerHandler = registerHandler
    self.unregisterHandler = unregisterHandler
    self.installHandler = installHandler
  }

  func registerHotKeys(correctSelection: Settings.HotKey, correctAll: Settings.HotKey, analyzeTone: Settings.HotKey) throws {
    try installHandlerIfNeeded()
    if registeredSelection == correctSelection,
       registeredAll == correctAll,
       registeredAnalyzeTone == analyzeTone,
       !hotKeyRefs.isEmpty
    {
      return
    }

    let previousSelection = registeredSelection
    let previousAll = registeredAll
    let previousAnalyzeTone = registeredAnalyzeTone
    unregisterAll()

    let correctSelectionID = HotKeyID.correctSelection.rawValue
    let correctAllID = HotKeyID.correctAll.rawValue
    let analyzeToneID = HotKeyID.analyzeTone.rawValue

    do {
      try registerHotKey(id: correctSelectionID, keyCode: correctSelection.keyCode, modifiers: correctSelection.modifiers)
      try registerHotKey(id: correctAllID, keyCode: correctAll.keyCode, modifiers: correctAll.modifiers)
      try registerHotKey(id: analyzeToneID, keyCode: analyzeTone.keyCode, modifiers: analyzeTone.modifiers)
      registeredSelection = correctSelection
      registeredAll = correctAll
      registeredAnalyzeTone = analyzeTone
    } catch {
      unregisterAll()
      if let previousSelection, let previousAll, let previousAnalyzeTone {
        do {
          try registerHotKey(id: correctSelectionID, keyCode: previousSelection.keyCode, modifiers: previousSelection.modifiers)
          try registerHotKey(id: correctAllID, keyCode: previousAll.keyCode, modifiers: previousAll.modifiers)
          try registerHotKey(id: analyzeToneID, keyCode: previousAnalyzeTone.keyCode, modifiers: previousAnalyzeTone.modifiers)
          registeredSelection = previousSelection
          registeredAll = previousAll
          registeredAnalyzeTone = previousAnalyzeTone
        } catch {
          registeredSelection = nil
          registeredAll = nil
          registeredAnalyzeTone = nil
          NSLog("[TextPolish] Failed to restore previous hotkeys: \(error)")
        }
      } else {
        registeredSelection = nil
        registeredAll = nil
        registeredAnalyzeTone = nil
      }
      throw error
    }
  }

  private func unregisterAll() {
    for (_, ref) in hotKeyRefs {
      unregisterHandler(ref)
    }
    hotKeyRefs.removeAll()
  }

  private func installHandlerIfNeeded() throws {
    guard handlerRef == nil else { return }
    handlerRef = try installHandler(self)
  }

  private static func defaultInstallHandler(_ manager: HotKeyManager) throws -> EventHandlerRef? {
    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    var handlerRef: EventHandlerRef?
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData else { return noErr }
        let userDataValue = UInt(bitPattern: userData)

        var hotKeyID = EventHotKeyID()
        let getStatus = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        if getStatus == noErr {
          let id = Int(hotKeyID.id)
          MainActor.assumeIsolated {
            let pointer = UnsafeMutableRawPointer(bitPattern: userDataValue)!
            let manager = Unmanaged<HotKeyManager>.fromOpaque(pointer).takeUnretainedValue()
            manager.onHotKey?(id)
          }
        }
        return noErr
      },
      1,
      &eventSpec,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(manager).toOpaque()),
      &handlerRef
    )

    guard status == noErr else { throw HotKeyManagerError.couldNotInstallHandler(status) }
    return handlerRef
  }

  private func registerHotKey(id: Int, keyCode: UInt32, modifiers: UInt32) throws {
    let ref = try registerHandler(id, keyCode, modifiers)
    hotKeyRefs[id] = ref
  }

  private static func defaultRegisterHandler(id: Int, keyCode: UInt32, modifiers: UInt32) throws -> EventHotKeyRef {
    let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
    var ref: EventHotKeyRef?

    let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status == eventHotKeyDuplicateErr {
      throw HotKeyManagerError.alreadyInUse
    }
    guard status == noErr else { throw HotKeyManagerError.couldNotRegisterHotKey(status) }
    guard let ref else { throw HotKeyManagerError.couldNotRegisterHotKey(status) }
    return ref
  }

  private static func defaultUnregisterHandler(_ ref: EventHotKeyRef) {
    UnregisterEventHotKey(ref)
  }

  static func checkHotKeyInUse(keyCode: UInt32, modifiers: UInt32) -> Bool {
    let hotKeyID = EventHotKeyID(signature: 0x54455354, id: 0)
    var ref: EventHotKeyRef?

    let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status == eventHotKeyDuplicateErr {
      return true
    }
    if status == noErr, let ref = ref {
      UnregisterEventHotKey(ref)
    }
    return false
  }

  static func isHotKeyInUse(
    hotKey: Settings.HotKey,
    ignoring ignored: [Settings.HotKey],
    checker: (UInt32, UInt32) -> Bool = HotKeyManager.checkHotKeyInUse
  ) -> Bool {
    if ignored.contains(hotKey) {
      return false
    }
    return checker(hotKey.keyCode, hotKey.modifiers)
  }
}
