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
    let _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")

    let delegate = AppDelegate()
    delegate.debugFinishLaunching()

    XCTAssertTrue(delegate.debugHasMidnightRefreshTimer)
    XCTAssertEqual(delegate.debugCorrectionOperationTimeout, .seconds(24))
    XCTAssertEqual(delegate.debugToneOperationTimeout, .seconds(22))

    delegate.applyFallbackSettingToggle()

    XCTAssertEqual(delegate.debugCorrectionOperationTimeout, .seconds(44))
    XCTAssertEqual(delegate.debugToneOperationTimeout, .seconds(42))
  }

  @MainActor
  func testAppDelegateDebouncesRapidRegisteredHotKeys() {
    let _ = NSApplication.shared
    let delegate = AppDelegate()
    let start = ContinuousClock.now

    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.correctSelection.rawValue, now: start))
    XCTAssertFalse(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.correctSelection.rawValue, now: start + .milliseconds(200)))
    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.correctSelection.rawValue, now: start + .milliseconds(400)))
    XCTAssertTrue(delegate.debugHandleRegisteredHotKey(HotKeyManager.HotKeyID.analyzeTone.rawValue, now: start + .milliseconds(450)))
  }
}
