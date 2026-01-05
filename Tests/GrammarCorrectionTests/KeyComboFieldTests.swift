import XCTest
import AppKit
import Carbon
@testable import GrammarCorrection

final class KeyComboFieldTests: XCTestCase {
    var keyComboField: KeyComboField!
    var testWindow: NSWindow!

    override func setUp() {
        super.setUp()
        keyComboField = KeyComboField(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        testWindow = NSWindow()
        testWindow.contentView = keyComboField
    }

    override func tearDown() {
        keyComboField = nil
        testWindow = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(keyComboField, "KeyComboField should be initialized")
        XCTAssertNil(keyComboField.hotKey, "HotKey should be nil initially")
    }

    func testDefaultDisplayString() {
        XCTAssertEqual(keyComboField.textField.stringValue, "Click to set", "Should show default text")
        XCTAssertEqual(keyComboField.textField.textColor, .secondaryLabelColor, "Should have secondary label color")
    }

    func testLoadFromHotKey() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))

        // When
        keyComboField.loadFromHotKey(hotKey)

        // Then
        XCTAssertEqual(keyComboField.hotKey, hotKey, "HotKey should be set")
        XCTAssertEqual(keyComboField.textField.textColor, .labelColor, "Should have label color")
    }

    func testDisplayStringWithCommandKey() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))

        // When
        keyComboField.hotKey = hotKey

        // Then
        XCTAssertEqual(keyComboField.textField.stringValue, "⌘G", "Should display ⌘G")
    }

    func testDisplayStringWithMultipleModifiers() {
        // Given
        let hotKey = Settings.HotKey(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey)
        )

        // When
        keyComboField.hotKey = hotKey

        // Then
        XCTAssertEqual(keyComboField.textField.stringValue, "⇧⌃⌥⌘G", "Should display all modifiers")
    }

    func testDisplayStringWithShiftOnly() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(shiftKey))

        // When
        keyComboField.hotKey = hotKey

        // Then
        XCTAssertEqual(keyComboField.textField.stringValue, "⇧G", "Should display ⇧G")
    }

    func testDisplayStringWithControlOnly() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey))

        // When
        keyComboField.hotKey = hotKey

        // Then
        XCTAssertEqual(keyComboField.textField.stringValue, "⌃G", "Should display ⌃G")
    }

    func testDisplayStringWithOptionOnly() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(optionKey))

        // When
        keyComboField.hotKey = hotKey

        // Then
        XCTAssertEqual(keyComboField.textField.stringValue, "⌥G", "Should display ⌥G")
    }

    func testDisplayStringWithNoModifiers() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: 0)

        // When
        keyComboField.hotKey = hotKey

        // Then
        XCTAssertEqual(keyComboField.textField.stringValue, "G", "Should display just G")
    }

    func testHotKeyPropertyDidSet() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey))

        // When
        keyComboField.hotKey = hotKey

        // Then
        XCTAssertEqual(keyComboField.textField.stringValue, "⌘T", "Display should update when hotKey is set")
    }

    func testKeyComboFieldHasGestureRecognizer() {
        let gestureRecognizers = keyComboField.gestureRecognizers
        XCTAssertTrue(gestureRecognizers.contains { $0 is NSClickGestureRecognizer }, "Should have click gesture recognizer")
    }

    func testVisualFeedbackOnRecording() {
        // Given
        let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
        keyComboField.hotKey = hotKey

        // Verify initial state
        XCTAssertEqual(keyComboField.textField.textColor, .labelColor, "Should have label color initially")

        // Reset and verify
        keyComboField.hotKey = nil
        XCTAssertEqual(keyComboField.textField.textColor, .secondaryLabelColor, "Should have secondary label color when no hotkey")
    }

    func testMultipleHotKeyChanges() {
        // Given
        let hotKey1 = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
        let hotKey2 = Settings.HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(shiftKey))

        // When
        keyComboField.hotKey = hotKey1
        keyComboField.hotKey = hotKey2

        // Then
        XCTAssertEqual(keyComboField.hotKey, hotKey2, "Should have the last hotkey set")
        XCTAssertEqual(keyComboField.textField.stringValue, "⇧T", "Should display the last hotkey")
    }

    func testEquatable() {
        // Given
        let hotKey1 = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
        let hotKey2 = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey))
        let hotKey3 = Settings.HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(cmdKey))

        // Then
        XCTAssertEqual(hotKey1, hotKey2, "HotKeys with same values should be equal")
        XCTAssertNotEqual(hotKey1, hotKey3, "HotKeys with different values should not be equal")
    }

    func testDefaultHotKeys() {
        // Test that default hotkeys are properly formatted
        XCTAssertEqual(Settings.HotKey.correctSelectionDefault.displayString.count > 0, true, "Default selection hotkey should have display string")
        XCTAssertEqual(Settings.HotKey.correctAllDefault.displayString.count > 0, true, "Default all hotkey should have display string")
        XCTAssertEqual(Settings.HotKey.analyzeToneDefault.displayString.count > 0, true, "Default tone hotkey should have display string")
    }
}

// MARK: - Display String Tests
extension KeyComboFieldTests {
    func testDisplayString_AllModifierCombinations() {
        let testCases: [(UInt32, String)] = [
            (0, "G"),
            (UInt32(shiftKey), "⇧G"),
            (UInt32(controlKey), "⌃G"),
            (UInt32(optionKey), "⌥G"),
            (UInt32(cmdKey), "⌘G"),
            (UInt32(shiftKey | controlKey), "⇧⌃G"),
            (UInt32(shiftKey | optionKey), "⇧⌥G"),
            (UInt32(shiftKey | cmdKey), "⇧⌘G"),
            (UInt32(controlKey | optionKey), "⌃⌥G"),
            (UInt32(controlKey | cmdKey), "⌃⌘G"),
            (UInt32(optionKey | cmdKey), "⌥⌘G"),
            (UInt32(shiftKey | controlKey | optionKey), "⇧⌃⌥G"),
            (UInt32(shiftKey | controlKey | cmdKey), "⇧⌃⌘G"),
            (UInt32(shiftKey | optionKey | cmdKey), "⇧⌥⌘G"),
            (UInt32(controlKey | optionKey | cmdKey), "⌃⌥⌘G"),
            (UInt32(shiftKey | controlKey | optionKey | cmdKey), "⇧⌃⌥⌘G"),
        ]

        for (modifiers, expected) in testCases {
            let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: modifiers)
            XCTAssertEqual(hotKey.displayString, expected, "Failed for modifiers: \(modifiers)")
        }
    }
}
