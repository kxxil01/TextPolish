import Carbon

final class HotKeyManager {
  enum HotKeyID: Int {
    case correctSelection = 1
    case correctAll = 2
  }

  enum HotKeyManagerError: Error {
    case couldNotInstallHandler(OSStatus)
    case couldNotRegisterHotKey(OSStatus)
  }

  var onHotKey: ((Int) -> Void)?

  private var handlerRef: EventHandlerRef?
  private var hotKeyRefs: [EventHotKeyRef?] = []

  private let signature: OSType = 0x47434F52 // 'GCOR'

  func registerDefaultHotKeys() throws {
    try installHandlerIfNeeded()

    // ⌃⌥⌘G
    try registerHotKey(
      id: HotKeyID.correctSelection.rawValue,
      keyCode: UInt32(kVK_ANSI_G),
      modifiers: UInt32(controlKey | optionKey | cmdKey)
    )

    // ⌃⌥⌘⇧G
    try registerHotKey(
      id: HotKeyID.correctAll.rawValue,
      keyCode: UInt32(kVK_ANSI_G),
      modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey)
    )
  }

  private func installHandlerIfNeeded() throws {
    guard handlerRef == nil else { return }

    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

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
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &handlerRef
    )

    guard status == noErr else { throw HotKeyManagerError.couldNotInstallHandler(status) }
  }

  private func registerHotKey(id: Int, keyCode: UInt32, modifiers: UInt32) throws {
    let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(id))
    var ref: EventHotKeyRef?

    let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    guard status == noErr else { throw HotKeyManagerError.couldNotRegisterHotKey(status) }

    hotKeyRefs.append(ref)
  }
}
