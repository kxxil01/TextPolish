import Foundation
import XCTest
import AppKit
import Carbon

@testable import GrammarCorrection

final class SettingsHotKeyTests: XCTestCase {
  func testDisplayStringDefaults() {
    let control = "\u{2303}"
    let option = "\u{2325}"
    let command = "\u{2318}"
    let shift = "\u{21E7}"

    let selectionExpected = control + option + command + "G"
    let allExpected = shift + control + option + command + "G"

    XCTAssertEqual(Settings.HotKey.correctSelectionDefault.displayString, selectionExpected)
    XCTAssertEqual(Settings.HotKey.correctAllDefault.displayString, allExpected)
  }

  func testDisplayStringOrdersModifiers() {
    let modifiers = UInt32(shiftKey | controlKey | optionKey | cmdKey)
    let hotKey = Settings.HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: modifiers)
    XCTAssertEqual(hotKey.displayString, "\u{21E7}\u{2303}\u{2325}\u{2318}A")
  }

  func testDisplayStringSpecialKeys() {
    let returnKey = Settings.HotKey(keyCode: UInt32(kVK_Return), modifiers: 0)
    let spaceKey = Settings.HotKey(keyCode: UInt32(kVK_Space), modifiers: 0)

    XCTAssertEqual(returnKey.displayString, "\u{21A9}")
    XCTAssertEqual(spaceKey.displayString, "\u{2423}")
  }

  func testDisplayStringUnknownKeyUsesFallback() {
    let hotKey = Settings.HotKey(keyCode: 9999, modifiers: 0)
    XCTAssertEqual(hotKey.displayString, "?")
  }

  func testKeyEquivalentStringDefaultKey() {
    let keyCode = Settings.HotKey.correctSelectionDefault.keyCode
    XCTAssertEqual(Settings.HotKey.keyEquivalentString(keyCode: keyCode), "g")
  }

  func testKeyEquivalentStringSpecialKeys() {
    XCTAssertEqual(Settings.HotKey.keyEquivalentString(keyCode: UInt32(kVK_Return)), "\r")
    XCTAssertEqual(Settings.HotKey.keyEquivalentString(keyCode: UInt32(kVK_Tab)), "\t")
    XCTAssertEqual(Settings.HotKey.keyEquivalentString(keyCode: UInt32(kVK_Space)), " ")
  }

  func testKeyEquivalentStringUnknownKeyIsEmpty() {
    XCTAssertEqual(Settings.HotKey.keyEquivalentString(keyCode: 9999), "")
  }

  func testModifierMaskMapping() {
    let modifiers = Settings.HotKey.correctSelectionDefault.modifiers
    let mask = Settings.HotKey.modifierMask(modifiers: modifiers)

    XCTAssertTrue(mask.contains(.control))
    XCTAssertTrue(mask.contains(.option))
    XCTAssertTrue(mask.contains(.command))
    XCTAssertFalse(mask.contains(.shift))
  }

  func testModifierMaskMappingAllFlags() {
    let modifiers = UInt32(shiftKey | controlKey | optionKey | cmdKey)
    let mask = Settings.HotKey.modifierMask(modifiers: modifiers)

    XCTAssertTrue(mask.contains(.shift))
    XCTAssertTrue(mask.contains(.control))
    XCTAssertTrue(mask.contains(.option))
    XCTAssertTrue(mask.contains(.command))
  }

  func testModifierMaskMappingEmpty() {
    let mask = Settings.HotKey.modifierMask(modifiers: 0)
    XCTAssertTrue(mask.isEmpty)
  }

  func testCodableRoundTripPreservesHotKeys() throws {
    let selection = Settings.HotKey(keyCode: 12, modifiers: 34)
    let all = Settings.HotKey(keyCode: 56, modifiers: 78)
    let settings = Settings(hotKeyCorrectSelection: selection, hotKeyCorrectAll: all)

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.hotKeyCorrectSelection, selection)
    XCTAssertEqual(decoded.hotKeyCorrectAll, all)
  }

  func testDecodeDefaultsWhenMissingHotKeys() throws {
    let json = """
    {
      "provider": "gemini",
      "requestTimeoutSeconds": 10
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.hotKeyCorrectSelection, Settings.HotKey.correctSelectionDefault)
    XCTAssertEqual(decoded.hotKeyCorrectAll, Settings.HotKey.correctAllDefault)
  }

  func testDecodeDefaultsWhenJsonEmpty() throws {
    let data = Data("{}".utf8)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.provider, .gemini)
    XCTAssertEqual(decoded.requestTimeoutSeconds, 20)
    XCTAssertEqual(decoded.activationDelayMilliseconds, 80)
    XCTAssertEqual(decoded.selectAllDelayMilliseconds, 60)
    XCTAssertEqual(decoded.copySettleDelayMilliseconds, 20)
    XCTAssertEqual(decoded.copyTimeoutMilliseconds, 900)
    XCTAssertEqual(decoded.pasteSettleDelayMilliseconds, 25)
    XCTAssertEqual(decoded.postPasteDelayMilliseconds, 180)
    XCTAssertEqual(decoded.timingProfiles, [:])
    XCTAssertEqual(decoded.fallbackToOpenRouterOnGeminiError, false)
    XCTAssertEqual(decoded.correctionLanguage, .auto)
    XCTAssertEqual(decoded.geminiModel, "gemini-2.0-flash-lite-001")
    XCTAssertEqual(decoded.openRouterModel, "meta-llama/llama-3.2-3b-instruct:free")
    XCTAssertEqual(decoded.hotKeyCorrectSelection, .correctSelectionDefault)
    XCTAssertEqual(decoded.hotKeyCorrectAll, .correctAllDefault)
  }

  func testDecodeUnknownProviderDefaultsToGemini() throws {
    let json = """
    {
      "provider": "unknown",
      "requestTimeoutSeconds": 10
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.provider, .gemini)
  }

  func testProviderEncodeDecodeRoundTrip() throws {
    let settings = Settings(provider: .openRouter)
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.provider, .openRouter)
  }

  func testDefaultsMatchExpectedValues() {
    let defaults = Settings.defaults()

    XCTAssertEqual(defaults.provider, .gemini)
    XCTAssertEqual(defaults.requestTimeoutSeconds, 20)
    XCTAssertEqual(defaults.activationDelayMilliseconds, 80)
    XCTAssertEqual(defaults.selectAllDelayMilliseconds, 60)
    XCTAssertEqual(defaults.copySettleDelayMilliseconds, 20)
    XCTAssertEqual(defaults.copyTimeoutMilliseconds, 900)
    XCTAssertEqual(defaults.pasteSettleDelayMilliseconds, 25)
    XCTAssertEqual(defaults.postPasteDelayMilliseconds, 180)
    XCTAssertEqual(defaults.timingProfiles, [:])
    XCTAssertEqual(defaults.fallbackToOpenRouterOnGeminiError, false)
    XCTAssertEqual(defaults.correctionLanguage, .auto)
    XCTAssertEqual(defaults.geminiModel, "gemini-2.0-flash-lite-001")
    XCTAssertEqual(defaults.openRouterModel, "meta-llama/llama-3.2-3b-instruct:free")
    XCTAssertEqual(defaults.hotKeyCorrectSelection, .correctSelectionDefault)
    XCTAssertEqual(defaults.hotKeyCorrectAll, .correctAllDefault)
  }

  func testDecodeTimingProfiles() throws {
    let json = """
    {
      "timingProfiles": {
        "com.example.app": {
          "copyTimeoutMilliseconds": 1200,
          "pasteSettleDelayMilliseconds": 40
        }
      }
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    let profile = decoded.timingProfiles["com.example.app"]
    XCTAssertEqual(profile?.copyTimeoutMilliseconds, 1200)
    XCTAssertEqual(profile?.pasteSettleDelayMilliseconds, 40)
  }

  func testTimingProfileLookupPrefersBundleIdentifier() {
    let bundleProfile = Settings.TimingProfile(copyTimeoutMilliseconds: 1200)
    let nameProfile = Settings.TimingProfile(copyTimeoutMilliseconds: 800)
    let settings = Settings(timingProfiles: [
      "com.example.app": bundleProfile,
      "ExampleApp": nameProfile
    ])

    let resolved = settings.timingProfile(bundleIdentifier: "com.example.app", appName: "ExampleApp")
    XCTAssertEqual(resolved, bundleProfile)
  }

  func testTimingProfileLookupFallsBackToName() {
    let nameProfile = Settings.TimingProfile(copyTimeoutMilliseconds: 800)
    let settings = Settings(timingProfiles: [
      "ExampleApp": nameProfile
    ])

    let resolved = settings.timingProfile(bundleIdentifier: nil, appName: "ExampleApp")
    XCTAssertEqual(resolved, nameProfile)
  }

  func testDecodeCorrectionLanguageEnglish() throws {
    let json = """
    {
      "correctionLanguage": "en-US"
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.correctionLanguage, .englishUS)
  }

  func testDecodeCorrectionLanguageIndonesian() throws {
    let json = """
    {
      "correctionLanguage": "id-ID"
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.correctionLanguage, .indonesian)
  }

  func testDecodeCorrectionLanguageUnknownDefaultsToAuto() throws {
    let json = """
    {
      "correctionLanguage": "klingon"
    }
    """
    let data = Data(json.utf8)
    let decoded = try JSONDecoder().decode(Settings.self, from: data)

    XCTAssertEqual(decoded.correctionLanguage, .auto)
  }
}
