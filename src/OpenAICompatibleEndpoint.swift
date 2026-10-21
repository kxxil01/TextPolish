import Foundation

/// Where an OpenAI-format chat request goes and how it signs in: OpenAI itself, or the Custom provider,
/// which is any service that speaks the same API.
struct OpenAICompatibleEndpoint: Sendable {
  let provider: Settings.Provider
  /// The name in errors and logs.
  let name: String
  let baseURL: String
  let model: String
  let keychainAccount: String
  let keyFromSettings: String?
  let envKeys: [String]
  /// Local servers often need no key; requests then go without an Authorization header.
  let requiresApiKey: Bool
  let maxAttempts: Int
  let minSimilarity: Double
  let extraInstruction: String?

  static func openAI(_ settings: Settings) -> OpenAICompatibleEndpoint {
    OpenAICompatibleEndpoint(
      provider: .openAI,
      name: "OpenAI",
      baseURL: settings.openAIBaseURL,
      model: settings.openAIModel,
      keychainAccount: "openAIApiKey",
      keyFromSettings: settings.openAIApiKey,
      envKeys: ["OPENAI_API_KEY"],
      requiresApiKey: true,
      maxAttempts: settings.openAIMaxAttempts,
      minSimilarity: settings.openAIMinSimilarity,
      extraInstruction: settings.openAIExtraInstruction
    )
  }

  static func custom(_ settings: Settings) -> OpenAICompatibleEndpoint {
    let custom = settings.customProvider
    return OpenAICompatibleEndpoint(
      provider: .custom,
      name: "Custom provider",
      baseURL: custom.baseURL,
      model: custom.model,
      keychainAccount: customKeychainAccount,
      keyFromSettings: custom.apiKey,
      envKeys: ["TEXTPOLISH_CUSTOM_API_KEY"],
      requiresApiKey: false,
      maxAttempts: custom.maxAttempts,
      minSimilarity: custom.minSimilarity,
      extraInstruction: custom.extraInstruction
    )
  }

  static let customKeychainAccount = "customApiKey"

  /// The key from the keychain, then the settings file, then the environment; nil when none is set.
  /// Reading the keychain can show a prompt, so call this off the main thread.
  func apiKey(keychainService: String) -> String? {
    do {
      if let key = try Keychain.getConfiguredPassword(primaryService: keychainService, account: keychainAccount),
         !key.isEmpty
      {
        return key
      }
    } catch {
      TPLogger.log("Failed to read \(name) keychain: \(error)")
    }
    if let key = keyFromSettings?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
      return key
    }
    for envKey in envKeys {
      let value = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !value.isEmpty {
        return value
      }
    }
    return nil
  }
}

/// An OpenAI-format error from the Custom provider, worded with its name.
struct CustomProviderError: LocalizedError {
  let underlying: OpenAICorrector.OpenAIError

  var errorDescription: String? {
    underlying.message(for: "Custom provider")
  }
}
