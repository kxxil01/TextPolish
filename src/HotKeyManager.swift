import Carbon
import AppKit

final class HotKeyManager {
  typealias RegisterHandler = (_ id: Int, _ keyCode: UInt32, _ modifiers: UInt32) throws -> EventHotKeyRef
  typealias UnregisterHandler = (_ ref: EventHotKeyRef) -> Void
  typealias InstallHandler = (_ manager: HotKeyManager) throws -> EventHandlerRef?

  enum HotKeyID: Int {
    case polish = 1
    case analyzeTone = 3
  }

  /// Style shortcuts use IDs from here up, one per `Settings.PolishStyle` in `allCases` order.
  private static let firstStyleHotKeyID = 10

  static func styleHotKeyID(index: Int) -> Int {
    firstStyleHotKeyID + index
  }

  static func styleIndex(forHotKeyID id: Int) -> Int? {
    id >= firstStyleHotKeyID ? id - firstStyleHotKeyID : nil
  }

  enum HotKeyManagerError: Error {
    case couldNotInstallHandler(OSStatus)
    case couldNotRegisterHotKey(OSStatus)
    case alreadyInUse
  }

  var onHotKey: ((Int) -> Void)?

  private var handlerRef: EventHandlerRef?
  private var hotKeyRefs: [Int: EventHotKeyRef] = [:]
  private var registeredPolish: Settings.HotKey?
  private var registeredAnalyzeTone: Settings.HotKey?
  private var registeredStyles: [Int: Settings.HotKey] = [:]

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

  func registerHotKeys(
    polish: Settings.HotKey,
    analyzeTone: Settings.HotKey,
    styles: [Int: Settings.HotKey] = [:]
  ) throws {
    try installHandlerIfNeeded()
    if registeredPolish == polish,
       registeredAnalyzeTone == analyzeTone,
       registeredStyles == styles,
       hotKeyRefs[HotKeyID.polish.rawValue] != nil,
       hotKeyRefs[HotKeyID.analyzeTone.rawValue] != nil,
       styles.keys.allSatisfy({ hotKeyRefs[$0] != nil })
    {
      return
    }

    let previousPolish = registeredPolish
    let previousAnalyzeTone = registeredAnalyzeTone
    unregisterAll()

    let polishID = HotKeyID.polish.rawValue
    let analyzeToneID = HotKeyID.analyzeTone.rawValue

    var firstError: Error?

    func registerWithFallback(
      id: Int,
      desired: Settings.HotKey,
      previous: Settings.HotKey?
    ) -> Settings.HotKey? {
      do {
        try registerHotKey(id: id, keyCode: desired.keyCode, modifiers: desired.modifiers)
        return desired
      } catch let desiredError {
        if firstError == nil {
          firstError = desiredError
        }

        guard let previous, previous != desired else {
          return nil
        }

        do {
          try registerHotKey(id: id, keyCode: previous.keyCode, modifiers: previous.modifiers)
          return previous
        } catch {
          TPLogger.log("Failed to restore hotkey id=\(id): \(error)")
          return nil
        }
      }
    }

    registeredPolish = registerWithFallback(id: polishID, desired: polish, previous: previousPolish)
    registeredAnalyzeTone = registerWithFallback(id: analyzeToneID, desired: analyzeTone, previous: previousAnalyzeTone)

    // Style shortcuts are optional extras: one that fails is skipped without touching the others.
    registeredStyles = [:]
    for (id, hotKey) in styles.sorted(by: { $0.key < $1.key }) {
      do {
        try registerHotKey(id: id, keyCode: hotKey.keyCode, modifiers: hotKey.modifiers)
        registeredStyles[id] = hotKey
      } catch {
        if firstError == nil {
          firstError = error
        }
      }
    }

    if let firstError {
      throw firstError
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
            guard let pointer = UnsafeMutableRawPointer(bitPattern: userDataValue) else { return }
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

extension HotKeyManager.HotKeyManagerError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .couldNotInstallHandler(let status):
      return "Could not install global hotkey handler (OSStatus \(status))."
    case .couldNotRegisterHotKey(let status):
      return "Could not register global shortcut (OSStatus \(status))."
    case .alreadyInUse:
      return "The shortcut is already used by another application."
    }
  }
}
