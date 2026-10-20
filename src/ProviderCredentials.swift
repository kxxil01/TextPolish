import Foundation

enum ProviderCredentials {
  /// Whether a key is set up for `provider`, checked without reading the secret.
  /// Reading it can show a keychain prompt that blocks the calling thread until the user answers.
  static func isConfigured(for provider: Settings.Provider, settings: Settings) -> Bool {
    let keychainService = Keychain.primaryService(bundleIdentifier: Bundle.main.bundleIdentifier)

    let credentialSource: (account: String, envKeys: [String], settingsValue: String?)
    switch provider {
    case .gemini:
      credentialSource = ("geminiApiKey", ["GEMINI_API_KEY", "GOOGLE_API_KEY"], settings.geminiApiKey)
    case .openRouter:
      credentialSource = ("openRouterApiKey", ["OPENROUTER_API_KEY"], settings.openRouterApiKey)
    case .openAI:
      credentialSource = ("openAIApiKey", ["OPENAI_API_KEY"], settings.openAIApiKey)
    case .anthropic:
      credentialSource = ("anthropicApiKey", ["ANTHROPIC_API_KEY"], settings.anthropicApiKey)
    }

    if Keychain.hasConfiguredPassword(
      primaryService: keychainService,
      account: credentialSource.account
    ) {
      return true
    }

    if let settingsValue = credentialSource.settingsValue?.trimmingCharacters(in: .whitespacesAndNewlines),
       !settingsValue.isEmpty {
      return true
    }

    for envKey in credentialSource.envKeys {
      let envValue = ProcessInfo.processInfo.environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !envValue.isEmpty {
        return true
      }
    }

    return false
  }
}
