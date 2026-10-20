import AppKit
import Carbon
import XCTest

@testable import GrammarCorrection

final class AppDelegateSupportTests: XCTestCase {
  func testStatusItemCountFormatter() {
    XCTAssertEqual(StatusItemCountFormatter.title(for: 0), "")
    XCTAssertEqual(StatusItemCountFormatter.title(for: 3), " 3")
    XCTAssertEqual(StatusItemCountFormatter.title(for: 120), " 99+")
  }

  func testDailyResetSchedulerTargetsNextMidnight() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let now = Date(timeIntervalSince1970: 1_709_668_800) // 2024-03-06 10:00:00 UTC
    let nextReset = DailyResetScheduler.nextResetDate(after: now, calendar: calendar)
    let components = calendar.dateComponents([.hour, .minute, .second], from: nextReset)

    XCTAssertEqual(components.hour, 0)
    XCTAssertEqual(components.minute, 0)
    XCTAssertEqual(components.second, 0)
    XCTAssertGreaterThan(nextReset, now)
  }

  func testHotKeyPressDebouncerRejectsRapidRepeatForSameHotKey() {
    var debouncer = HotKeyPressDebouncer(cooldown: .milliseconds(350))
    let start = ContinuousClock.now

    XCTAssertTrue(debouncer.shouldAccept(id: 1, now: start))
    XCTAssertFalse(debouncer.shouldAccept(id: 1, now: start + .milliseconds(200)))
    XCTAssertTrue(debouncer.shouldAccept(id: 1, now: start + .milliseconds(350)))
  }

  func testHotKeyPressDebouncerTracksEachHotKeyIndependently() {
    var debouncer = HotKeyPressDebouncer(cooldown: .milliseconds(350))
    let start = ContinuousClock.now

    XCTAssertTrue(debouncer.shouldAccept(id: 1, now: start))
    XCTAssertTrue(debouncer.shouldAccept(id: 2, now: start + .milliseconds(50)))
    XCTAssertFalse(debouncer.shouldAccept(id: 1, now: start + .milliseconds(100)))
    XCTAssertFalse(debouncer.shouldAccept(id: 2, now: start + .milliseconds(150)))
    XCTAssertTrue(debouncer.shouldAccept(id: 2, now: start + .milliseconds(400)))
  }

  func testEscapeKeyCancellationMatcherAcceptsBareEscapeOnly() {
    XCTAssertTrue(EscapeKeyCancellationMatcher.shouldCancel(keyCode: UInt16(kVK_Escape), modifiers: []))
    XCTAssertFalse(EscapeKeyCancellationMatcher.shouldCancel(keyCode: UInt16(kVK_Escape), modifiers: [.command]))
    XCTAssertFalse(EscapeKeyCancellationMatcher.shouldCancel(keyCode: UInt16(kVK_Return), modifiers: []))
  }

  func testHotKeyPromptInterpreterUsesBareEscapeAndTabAsControls() {
    XCTAssertEqual(
      HotKeyPromptInterpreter.interpret(
        eventType: .keyDown,
        keyCode: UInt16(kVK_Escape),
        modifiers: []
      ),
      .cancel
    )
    XCTAssertEqual(
      HotKeyPromptInterpreter.interpret(
        eventType: .keyDown,
        keyCode: UInt16(kVK_Tab),
        modifiers: []
      ),
      .reset
    )
  }

  func testHotKeyPromptInterpreterAllowsModifiedEscapeAndTab() {
    XCTAssertEqual(
      HotKeyPromptInterpreter.interpret(
        eventType: .keyDown,
        keyCode: UInt16(kVK_Escape),
        modifiers: [.command]
      ),
      .capture(Settings.HotKey(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey)))
    )
    XCTAssertEqual(
      HotKeyPromptInterpreter.interpret(
        eventType: .keyDown,
        keyCode: UInt16(kVK_Tab),
        modifiers: [.shift]
      ),
      .capture(Settings.HotKey(keyCode: UInt32(kVK_Tab), modifiers: UInt32(shiftKey)))
    )
  }

  @MainActor
  func testAppDelegateSchedulesDailyResetAndRefreshesTimeoutsWhenFallbackToggles() {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")

    let delegate = AppDelegate()
    delegate.debugFinishLaunching()

    XCTAssertTrue(delegate.debugHasMidnightRefreshTimer)
    let correctionTimeout = delegate.debugCorrectionOperationTimeout
    let toneTimeout = delegate.debugToneOperationTimeout
    XCTAssertNotNil(correctionTimeout)
    XCTAssertNotNil(toneTimeout)

    delegate.applyFallbackSettingToggle()

    // Fallback no longer multiplies timeout — values stay the same
    XCTAssertEqual(delegate.debugCorrectionOperationTimeout, correctionTimeout)
    XCTAssertEqual(delegate.debugToneOperationTimeout, toneTimeout)
  }

  @MainActor
  func testAppDelegateDebouncesRapidRegisteredHotKeys() {
    _ = NSApplication.shared
    let delegate = AppDelegate()
    let start = ContinuousClock.now

    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.polish.rawValue, now: start))
    XCTAssertFalse(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.polish.rawValue, now: start + .milliseconds(200)))
    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.polish.rawValue, now: start + .milliseconds(400)))
    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.analyzeTone.rawValue, now: start + .milliseconds(450)))
  }

  @MainActor
  func testAppDelegateSettingsChangeRefreshesMenuShortcutLabels() async throws {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    defer { try? Settings.save(Settings()) }

    try Settings.save(Settings())
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()

    var updated = Settings.loadOrCreateDefault()
    updated.hotKeyPolish = Settings.HotKey(
      keyCode: UInt32(kVK_ANSI_P),
      modifiers: UInt32(controlKey | optionKey | cmdKey)
    )
    NotificationCenter.default.post(name: .settingsDidChange, object: updated)
    // The observer applies settings in a main-actor Task, so wait for it instead of a fixed delay.
    try await waitUntil { delegate.debugPolishMenuShortcut?.0 == "p" }

    let shortcut = try XCTUnwrap(delegate.debugPolishMenuShortcut)
    XCTAssertEqual(shortcut.0, "p")
    XCTAssertTrue(shortcut.1.contains(.command))
    XCTAssertTrue(shortcut.1.contains(.control))
    XCTAssertTrue(shortcut.1.contains(.option))
  }

  @MainActor
  func testPolishStyleMenuMarksNaturalByDefault() throws {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    defer { try? Settings.save(Settings()) }

    try Settings.save(Settings())
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()

    XCTAssertEqual(delegate.debugSelectedPolishStyleTitle, "Natural")
  }

  @MainActor
  func testAppDelegatePartialSettingSavePreservesNewerDiskAnthropicModel() throws {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    defer { try? Settings.save(Settings()) }

    var initial = Settings(provider: .anthropic, enableGeminiOpenRouterFallback: false)
    initial.anthropicModel = "claude-3-7-sonnet"
    try Settings.save(initial)

    let delegate = AppDelegate()
    delegate.debugFinishLaunching()

    var updatedOnDisk = Settings.loadOrCreateDefault()
    updatedOnDisk.anthropicModel = "claude-haiku-4-5"
    updatedOnDisk.enableGeminiOpenRouterFallback = false
    try Settings.save(updatedOnDisk)

    delegate.applyFallbackSettingToggle()

    let persisted = Settings.loadOrCreateDefault()
    XCTAssertEqual(persisted.anthropicModel, "claude-haiku-4-5")
    XCTAssertTrue(persisted.enableGeminiOpenRouterFallback)
  }

  /// Suspends between checks so queued main-actor work can run. Returns at the deadline either way;
  /// the caller's assertions report the failure.
  @MainActor
  private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
  }
}
