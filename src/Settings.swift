import Foundation
import Carbon
import AppKit

struct Settings: Codable {
  private static let appSupportFolderName = "TextPolish"
  private static let legacyAppSupportFolderName = "GrammarCorrection"

  struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let correctSelectionDefault = HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey | cmdKey))
    static let correctAllDefault = HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
    static let analyzeToneDefault = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey | cmdKey))

    var displayString: String {
      var parts: [String] = []
      if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
      if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
      if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
      if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
      parts.append(keyCodeToString(keyCode))
      return parts.joined()
    }

    static func keyEquivalentString(keyCode: UInt32) -> String {
      let code = Int(keyCode)
      switch code {
      case kVK_Return: return "\r"
      case kVK_Tab: return "\t"
      case kVK_Space: return " "
      case kVK_ANSI_A: return "a"
      case kVK_ANSI_B: return "b"
      case kVK_ANSI_C: return "c"
      case kVK_ANSI_D: return "d"
      case kVK_ANSI_E: return "e"
      case kVK_ANSI_F: return "f"
      case kVK_ANSI_G: return "g"
      case kVK_ANSI_H: return "h"
      case kVK_ANSI_I: return "i"
      case kVK_ANSI_J: return "j"
      case kVK_ANSI_K: return "k"
      case kVK_ANSI_L: return "l"
      case kVK_ANSI_M: return "m"
      case kVK_ANSI_N: return "n"
      case kVK_ANSI_O: return "o"
      case kVK_ANSI_P: return "p"
      case kVK_ANSI_Q: return "q"
      case kVK_ANSI_R: return "r"
      case kVK_ANSI_S: return "s"
      case kVK_ANSI_T: return "t"
      case kVK_ANSI_U: return "u"
      case kVK_ANSI_V: return "v"
      case kVK_ANSI_W: return "w"
      case kVK_ANSI_X: return "x"
      case kVK_ANSI_Y: return "y"
      case kVK_ANSI_Z: return "z"
      case kVK_ANSI_0: return "0"
      case kVK_ANSI_1: return "1"
      case kVK_ANSI_2: return "2"
      case kVK_ANSI_3: return "3"
      case kVK_ANSI_4: return "4"
      case kVK_ANSI_5: return "5"
      case kVK_ANSI_6: return "6"
      case kVK_ANSI_7: return "7"
      case kVK_ANSI_8: return "8"
      case kVK_ANSI_9: return "9"
      case kVK_ANSI_Grave: return "`"
      case kVK_ANSI_Minus: return "-"
      case kVK_ANSI_Equal: return "="
      case kVK_ANSI_LeftBracket: return "["
      case kVK_ANSI_RightBracket: return "]"
      case kVK_ANSI_Backslash: return "\\"
      case kVK_ANSI_Semicolon: return ";"
      case kVK_ANSI_Quote: return "'"
      case kVK_ANSI_Comma: return ","
      case kVK_ANSI_Period: return "."
      case kVK_ANSI_Slash: return "/"
      default: return ""
      }
    }

    static func modifierMask(modifiers: UInt32) -> NSEvent.ModifierFlags {
      var mask: NSEvent.ModifierFlags = []
      if modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
      if modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
      if modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
      if modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
      return mask
    }

    private func keyCodeToString(_ code: UInt32) -> String {
      switch Int(code) {
      case kVK_Return: return "↩"
      case kVK_Tab: return "⇥"
      case kVK_Space: return "␣"
      case kVK_Delete: return "⌫"
      case kVK_Escape: return "⎋"
      case kVK_Command: return "⌘"
      case kVK_Shift: return "⇧"
      case kVK_CapsLock: return "⇪"
      case kVK_Option: return "⌥"
      case kVK_Control: return "⌃"
      case kVK_RightCommand: return "⌘"
      case kVK_RightShift: return "⇧"
      case kVK_RightOption: return "⌥"
      case kVK_RightControl: return "⌃"
      case kVK_F1: return "F1"
      case kVK_F2: return "F2"
      case kVK_F3: return "F3"
      case kVK_F4: return "F4"
      case kVK_F5: return "F5"
      case kVK_F6: return "F6"
      case kVK_F7: return "F7"
      case kVK_F8: return "F8"
      case kVK_F9: return "F9"
      case kVK_F10: return "F10"
      case kVK_F11: return "F11"
      case kVK_F12: return "F12"
      case kVK_ANSI_A: return "A"
      case kVK_ANSI_B: return "B"
      case kVK_ANSI_C: return "C"
      case kVK_ANSI_D: return "D"
      case kVK_ANSI_E: return "E"
      case kVK_ANSI_F: return "F"
      case kVK_ANSI_G: return "G"
      case kVK_ANSI_H: return "H"
      case kVK_ANSI_I: return "I"
      case kVK_ANSI_J: return "J"
      case kVK_ANSI_K: return "K"
      case kVK_ANSI_L: return "L"
      case kVK_ANSI_M: return "M"
      case kVK_ANSI_N: return "N"
      case kVK_ANSI_O: return "O"
      case kVK_ANSI_P: return "P"
      case kVK_ANSI_Q: return "Q"
      case kVK_ANSI_R: return "R"
      case kVK_ANSI_S: return "S"
      case kVK_ANSI_T: return "T"
      case kVK_ANSI_U: return "U"
      case kVK_ANSI_V: return "V"
      case kVK_ANSI_W: return "W"
      case kVK_ANSI_X: return "X"
      case kVK_ANSI_Y: return "Y"
      case kVK_ANSI_Z: return "Z"
      case kVK_ANSI_0: return "0"
      case kVK_ANSI_1: return "1"
      case kVK_ANSI_2: return "2"
      case kVK_ANSI_3: return "3"
      case kVK_ANSI_4: return "4"
      case kVK_ANSI_5: return "5"
      case kVK_ANSI_6: return "6"
      case kVK_ANSI_7: return "7"
      case kVK_ANSI_8: return "8"
      case kVK_ANSI_9: return "9"
      case kVK_ANSI_Grave: return "`"
      case kVK_ANSI_Minus: return "-"
      case kVK_ANSI_Equal: return "="
      case kVK_ANSI_LeftBracket: return "["
      case kVK_ANSI_RightBracket: return "]"
      case kVK_ANSI_Backslash: return "\\"
      case kVK_ANSI_Semicolon: return ";"
      case kVK_ANSI_Quote: return "'"
      case kVK_ANSI_Comma: return ","
      case kVK_ANSI_Period: return "."
      case kVK_ANSI_Slash: return "/"
      default: return "?"
      }
    }
  }

  struct TimingProfile: Codable, Sendable, Equatable {
    var activationDelayMilliseconds: Int?
    var selectAllDelayMilliseconds: Int?
    var copySettleDelayMilliseconds: Int?
    var copyTimeoutMilliseconds: Int?
    var pasteSettleDelayMilliseconds: Int?
    var postPasteDelayMilliseconds: Int?

    init(
      activationDelayMilliseconds: Int? = nil,
      selectAllDelayMilliseconds: Int? = nil,
      copySettleDelayMilliseconds: Int? = nil,
      copyTimeoutMilliseconds: Int? = nil,
      pasteSettleDelayMilliseconds: Int? = nil,
      postPasteDelayMilliseconds: Int? = nil
    ) {
      self.activationDelayMilliseconds = activationDelayMilliseconds
      self.selectAllDelayMilliseconds = selectAllDelayMilliseconds
      self.copySettleDelayMilliseconds = copySettleDelayMilliseconds
      self.copyTimeoutMilliseconds = copyTimeoutMilliseconds
      self.pasteSettleDelayMilliseconds = pasteSettleDelayMilliseconds
      self.postPasteDelayMilliseconds = postPasteDelayMilliseconds
    }
  }

  enum CorrectionLanguage: String, Codable, Sendable {
    case auto = "auto"
    case englishUS = "en-US"
    case indonesian = "id-ID"

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      switch raw {
      case "en-us", "en_us", "english", "english-us", "english_us":
        self = .englishUS
      case "id-id", "id_id", "indonesian", "bahasa", "bahasa-indonesia", "bahasa_indonesia", "id":
        self = .indonesian
      case "auto":
        fallthrough
      default:
        self = .auto
      }
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }

    var displayName: String {
      switch self {
      case .auto:
        return "Auto"
      case .englishUS:
        return "English (US)"
      case .indonesian:
        return "Indonesian"
      }
    }

    var promptInstruction: String? {
      switch self {
      case .auto:
        return nil
      case .englishUS:
        return "Language: English (US). Correct in English (US). Do not translate."
      case .indonesian:
        return "Language: Indonesian. Correct in Indonesian. Do not translate."
      }
    }
  }

  enum Provider: String, Codable {
    case gemini
    case openRouter
    case openAI
    case anthropic

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      self = Provider(rawValue: raw) ?? .gemini
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(rawValue)
    }
  }

  var provider: Provider
  var requestTimeoutSeconds: Double
  var activationDelayMilliseconds: Int
  var selectAllDelayMilliseconds: Int
  var copySettleDelayMilliseconds: Int
  var copyTimeoutMilliseconds: Int
  var pasteSettleDelayMilliseconds: Int
  var postPasteDelayMilliseconds: Int
  var timingProfiles: [String: TimingProfile]
  var correctionLanguage: CorrectionLanguage
  var hotKeyCorrectSelection: HotKey
  var hotKeyCorrectAll: HotKey
  var hotKeyAnalyzeTone: HotKey
  var fallbackToOpenRouterOnGeminiError: Bool
  var geminiApiKey: String?
  var geminiModel: String
  var geminiBaseURL: String
  var geminiMaxAttempts: Int
  var geminiMinSimilarity: Double
  var geminiExtraInstruction: String?
  var openRouterApiKey: String?
  var openRouterModel: String
  var openRouterBaseURL: String
  var openRouterMaxAttempts: Int
  var openRouterMinSimilarity: Double
  var openRouterExtraInstruction: String?
  var openAIApiKey: String?
  var openAIModel: String
  var openAIBaseURL: String
  var openAIMaxAttempts: Int
  var openAIMinSimilarity: Double
  var openAIExtraInstruction: String?
  var anthropicApiKey: String?
  var anthropicModel: String
  var anthropicBaseURL: String
  var anthropicMaxAttempts: Int
  var anthropicMinSimilarity: Double
  var anthropicExtraInstruction: String?

  init(
    provider: Provider = .gemini,
    requestTimeoutSeconds: Double = 20,
    activationDelayMilliseconds: Int = 80,
    selectAllDelayMilliseconds: Int = 60,
    copySettleDelayMilliseconds: Int = 20,
    copyTimeoutMilliseconds: Int = 900,
    pasteSettleDelayMilliseconds: Int = 25,
    postPasteDelayMilliseconds: Int = 180,
    timingProfiles: [String: TimingProfile] = [:],
    correctionLanguage: CorrectionLanguage = .auto,
    hotKeyCorrectSelection: HotKey = .correctSelectionDefault,
    hotKeyCorrectAll: HotKey = .correctAllDefault,
    hotKeyAnalyzeTone: HotKey = .analyzeToneDefault,
    fallbackToOpenRouterOnGeminiError: Bool = false,
    geminiApiKey: String? = nil,
    geminiModel: String = "gemini-2.0-flash-lite-001",
    geminiBaseURL: String = "https://generativelanguage.googleapis.com",
    geminiMaxAttempts: Int = 2,
    geminiMinSimilarity: Double = 0.65,
    geminiExtraInstruction: String? = nil,
    openRouterApiKey: String? = nil,
    openRouterModel: String = "meta-llama/llama-3.2-3b-instruct:free",
    openRouterBaseURL: String = "https://openrouter.ai/api/v1",
    openRouterMaxAttempts: Int = 2,
    openRouterMinSimilarity: Double = 0.65,
    openRouterExtraInstruction: String? = nil,
    openAIApiKey: String? = nil,
    openAIModel: String = "gpt-4o-mini",
    openAIBaseURL: String = "https://api.openai.com/v1",
    openAIMaxAttempts: Int = 2,
    openAIMinSimilarity: Double = 0.65,
    openAIExtraInstruction: String? = nil,
    anthropicApiKey: String? = nil,
    anthropicModel: String = "claude-haiku-4-5",
    anthropicBaseURL: String = "https://api.anthropic.com",
    anthropicMaxAttempts: Int = 2,
    anthropicMinSimilarity: Double = 0.65,
    anthropicExtraInstruction: String? = nil
  ) {
    self.provider = provider
    self.requestTimeoutSeconds = requestTimeoutSeconds
    self.activationDelayMilliseconds = activationDelayMilliseconds
    self.selectAllDelayMilliseconds = selectAllDelayMilliseconds
    self.copySettleDelayMilliseconds = copySettleDelayMilliseconds
    self.copyTimeoutMilliseconds = copyTimeoutMilliseconds
    self.pasteSettleDelayMilliseconds = pasteSettleDelayMilliseconds
    self.postPasteDelayMilliseconds = postPasteDelayMilliseconds
    self.timingProfiles = timingProfiles
    self.correctionLanguage = correctionLanguage
    self.hotKeyCorrectSelection = hotKeyCorrectSelection
    self.hotKeyCorrectAll = hotKeyCorrectAll
    self.hotKeyAnalyzeTone = hotKeyAnalyzeTone
    self.fallbackToOpenRouterOnGeminiError = fallbackToOpenRouterOnGeminiError
    self.geminiApiKey = geminiApiKey
    self.geminiModel = geminiModel
    self.geminiBaseURL = geminiBaseURL
    self.geminiMaxAttempts = geminiMaxAttempts
    self.geminiMinSimilarity = geminiMinSimilarity
    self.geminiExtraInstruction = geminiExtraInstruction
    self.openRouterApiKey = openRouterApiKey
    self.openRouterModel = openRouterModel
    self.openRouterBaseURL = openRouterBaseURL
    self.openRouterMaxAttempts = openRouterMaxAttempts
    self.openRouterMinSimilarity = openRouterMinSimilarity
    self.openRouterExtraInstruction = openRouterExtraInstruction
    self.openAIApiKey = openAIApiKey
    self.openAIModel = openAIModel
    self.openAIBaseURL = openAIBaseURL
    self.openAIMaxAttempts = openAIMaxAttempts
    self.openAIMinSimilarity = openAIMinSimilarity
    self.openAIExtraInstruction = openAIExtraInstruction
    self.anthropicApiKey = anthropicApiKey
    self.anthropicModel = anthropicModel
    self.anthropicBaseURL = anthropicBaseURL
    self.anthropicMaxAttempts = anthropicMaxAttempts
    self.anthropicMinSimilarity = anthropicMinSimilarity
    self.anthropicExtraInstruction = anthropicExtraInstruction
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    provider = try container.decodeIfPresent(Provider.self, forKey: .provider) ?? .gemini
    requestTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? 20
    activationDelayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .activationDelayMilliseconds) ?? 80
    selectAllDelayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .selectAllDelayMilliseconds) ?? 60
    copySettleDelayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .copySettleDelayMilliseconds) ?? 20
    copyTimeoutMilliseconds = try container.decodeIfPresent(Int.self, forKey: .copyTimeoutMilliseconds) ?? 900
    pasteSettleDelayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .pasteSettleDelayMilliseconds) ?? 25
    postPasteDelayMilliseconds = try container.decodeIfPresent(Int.self, forKey: .postPasteDelayMilliseconds) ?? 180
    timingProfiles = try container.decodeIfPresent([String: TimingProfile].self, forKey: .timingProfiles) ?? [:]
    correctionLanguage = try container.decodeIfPresent(CorrectionLanguage.self, forKey: .correctionLanguage) ?? .auto
    hotKeyCorrectSelection = (try? container.decode(HotKey.self, forKey: .hotKeyCorrectSelection)) ?? .correctSelectionDefault
    hotKeyCorrectAll = (try? container.decode(HotKey.self, forKey: .hotKeyCorrectAll)) ?? .correctAllDefault
    hotKeyAnalyzeTone = (try? container.decode(HotKey.self, forKey: .hotKeyAnalyzeTone)) ?? .analyzeToneDefault
    fallbackToOpenRouterOnGeminiError =
      try container.decodeIfPresent(Bool.self, forKey: .fallbackToOpenRouterOnGeminiError) ?? false
    geminiApiKey = try container.decodeIfPresent(String.self, forKey: .geminiApiKey)
    geminiModel = try container.decodeIfPresent(String.self, forKey: .geminiModel) ?? "gemini-2.0-flash-lite-001"
    geminiBaseURL =
      try container.decodeIfPresent(String.self, forKey: .geminiBaseURL) ?? "https://generativelanguage.googleapis.com"
    geminiMaxAttempts = try container.decodeIfPresent(Int.self, forKey: .geminiMaxAttempts) ?? 2
    geminiMinSimilarity = try container.decodeIfPresent(Double.self, forKey: .geminiMinSimilarity) ?? 0.65
    geminiExtraInstruction = try container.decodeIfPresent(String.self, forKey: .geminiExtraInstruction)
    openRouterApiKey = try container.decodeIfPresent(String.self, forKey: .openRouterApiKey)
    openRouterModel =
      try container.decodeIfPresent(String.self, forKey: .openRouterModel) ?? "meta-llama/llama-3.2-3b-instruct:free"
    openRouterBaseURL = try container.decodeIfPresent(String.self, forKey: .openRouterBaseURL) ?? "https://openrouter.ai/api/v1"
    openRouterMaxAttempts = try container.decodeIfPresent(Int.self, forKey: .openRouterMaxAttempts) ?? 2
    openRouterMinSimilarity = try container.decodeIfPresent(Double.self, forKey: .openRouterMinSimilarity) ?? 0.65
    openRouterExtraInstruction = try container.decodeIfPresent(String.self, forKey: .openRouterExtraInstruction)
    openAIApiKey = try container.decodeIfPresent(String.self, forKey: .openAIApiKey)
    openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? "gpt-4o-mini"
    openAIBaseURL = try container.decodeIfPresent(String.self, forKey: .openAIBaseURL) ?? "https://api.openai.com/v1"
    openAIMaxAttempts = try container.decodeIfPresent(Int.self, forKey: .openAIMaxAttempts) ?? 2
    openAIMinSimilarity = try container.decodeIfPresent(Double.self, forKey: .openAIMinSimilarity) ?? 0.65
    openAIExtraInstruction = try container.decodeIfPresent(String.self, forKey: .openAIExtraInstruction)
    anthropicApiKey = try container.decodeIfPresent(String.self, forKey: .anthropicApiKey)
    anthropicModel = try container.decodeIfPresent(String.self, forKey: .anthropicModel) ?? "claude-haiku-4-5"
    anthropicBaseURL = try container.decodeIfPresent(String.self, forKey: .anthropicBaseURL) ?? "https://api.anthropic.com"
    anthropicMaxAttempts = try container.decodeIfPresent(Int.self, forKey: .anthropicMaxAttempts) ?? 2
    anthropicMinSimilarity = try container.decodeIfPresent(Double.self, forKey: .anthropicMinSimilarity) ?? 0.65
    anthropicExtraInstruction = try container.decodeIfPresent(String.self, forKey: .anthropicExtraInstruction)
  }

  private enum CodingKeys: String, CodingKey {
    case provider
    case requestTimeoutSeconds
    case activationDelayMilliseconds
    case selectAllDelayMilliseconds
    case copySettleDelayMilliseconds
    case copyTimeoutMilliseconds
    case pasteSettleDelayMilliseconds
    case postPasteDelayMilliseconds
    case timingProfiles
    case correctionLanguage
    case hotKeyCorrectSelection
    case hotKeyCorrectAll
    case hotKeyAnalyzeTone
    case fallbackToOpenRouterOnGeminiError
    case geminiApiKey
    case geminiModel
    case geminiBaseURL
    case geminiMaxAttempts
    case geminiMinSimilarity
    case geminiExtraInstruction
    case openRouterApiKey
    case openRouterModel
    case openRouterBaseURL
    case openRouterMaxAttempts
    case openRouterMinSimilarity
    case openRouterExtraInstruction
    case openAIApiKey
    case openAIModel
    case openAIBaseURL
    case openAIMaxAttempts
    case openAIMinSimilarity
    case openAIExtraInstruction
    case anthropicApiKey
    case anthropicModel
    case anthropicBaseURL
    case anthropicMaxAttempts
    case anthropicMinSimilarity
    case anthropicExtraInstruction
  }

  func timingProfile(bundleIdentifier: String?, appName: String?) -> TimingProfile? {
    if let bundleIdentifier, let profile = timingProfiles[bundleIdentifier] {
      return profile
    }
    if let appName, let profile = timingProfiles[appName] {
      return profile
    }
    return nil
  }

  static func defaults() -> Settings {
    Settings()
  }

  static func loadOrCreateDefault() -> Settings {
    let url = settingsFileURL()

    if let data = try? Data(contentsOf: url),
       let settings = try? JSONDecoder().decode(Settings.self, from: data)
    {
      return settings
    }

    let legacyURL = legacySettingsFileURL()
    if legacyURL != url,
       let data = try? Data(contentsOf: legacyURL),
       let settings = try? JSONDecoder().decode(Settings.self, from: data)
    {
      do {
        try save(settings)
      } catch {
        NSLog("[TextPolish] Could not migrate settings: \(error)")
      }
      return settings
    }

    let defaults = Settings.defaults()
    do {
      try save(defaults)
    } catch {
      NSLog("[TextPolish] Could not write default settings: \(error)")
    }

    return defaults
  }

  static func save(_ settings: Settings) throws {
    let url = settingsFileURL()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(settings)
    try data.write(to: url, options: [.atomic])
  }

  static func settingsFileURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base
      .appendingPathComponent(appSupportFolderName, isDirectory: true)
      .appendingPathComponent("settings.json", isDirectory: false)
  }

  static func legacySettingsFileURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base
      .appendingPathComponent(legacyAppSupportFolderName, isDirectory: true)
      .appendingPathComponent("settings.json", isDirectory: false)
  }
}
