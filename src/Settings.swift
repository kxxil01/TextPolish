import Foundation

struct Settings: Codable {
  private static let appSupportFolderName = "TextPolish"
  private static let legacyAppSupportFolderName = "GrammarCorrection"

  enum Provider: String, Codable {
    case gemini
    case openRouter

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

  init(
    provider: Provider = .gemini,
    requestTimeoutSeconds: Double = 20,
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
    openRouterExtraInstruction: String? = nil
  ) {
    self.provider = provider
    self.requestTimeoutSeconds = requestTimeoutSeconds
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
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    provider = try container.decodeIfPresent(Provider.self, forKey: .provider) ?? .gemini
    requestTimeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .requestTimeoutSeconds) ?? 20
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
