import Foundation

final class OpenRouterCorrector: GrammarCorrector, TextProcessor, RetryReporting, DiagnosticsProviderReporting {
  enum OpenRouterError: Error, LocalizedError {
    case missingApiKey
    case invalidBaseURL
    case requestFailed(Int, String?)
    case emptyResponse
    case overRewrite

    var errorDescription: String? {
      switch self {
      case .missingApiKey:
        return "Missing OpenRouter API key"
      case .invalidBaseURL:
        return "Invalid OpenRouter base URL"
      case .requestFailed(let status, let message):
        if status == 401 {
          return "OpenRouter unauthorized (401) — check API key"
        }
        if status == 402 {
          return "OpenRouter payment required (402) — add credits or use a free model (Provider → Set OpenRouter Model… / Detect OpenRouter Model…)"
        }
        if status == 404 {
          if let message, !message.isEmpty {
            return "OpenRouter request failed (404): \(message) — try Provider → Detect OpenRouter Model… (or Set OpenRouter Model…)"
          }
          return "OpenRouter model not found (404) — try Provider → Detect OpenRouter Model… (or Set OpenRouter Model…)"
        }
        if status == 429 {
          return "OpenRouter rate limited (429) — try again later"
        }
        if let message, !message.isEmpty {
          return "OpenRouter request failed (\(status)): \(message)"
        }
        return "OpenRouter request failed (\(status))"
      case .emptyResponse:
        return "OpenRouter returned no text"
      case .overRewrite:
        return "OpenRouter rewrote too much (try again or adjust model)"
      }
    }
  }

  // MARK: - TextProcessor Requirements

  let minSimilarity: Double

  static let fencedCodeBlockRegex = try! NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
  static let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`\\n]*`", options: [])
  static let discordTokenRegex = try! NSRegularExpression(pattern: "<[^>\\n]+>", options: [])
  static let urlRegex = try! NSRegularExpression(pattern: "https?://[^\\s]+", options: [])

  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let keychainAccount = "openRouterApiKey"
  private let keychainLabel = "TextPolish — OpenRouter API Key"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let maxAttempts: Int
  private let extraInstruction: String?
  private let correctionLanguage: Settings.CorrectionLanguage
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .openRouter }
  var diagnosticsModel: String { model }

  init(settings: Settings) throws {
    keyFromSettings = settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.openRouterBaseURL) else { throw OpenRouterError.invalidBaseURL }

    self.baseURL = baseURL
    self.model = settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
    self.timeoutSeconds = settings.requestTimeoutSeconds
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    self.session = URLSession(configuration: configuration)
    self.maxAttempts = max(1, settings.openRouterMaxAttempts)
    self.minSimilarity = max(0.0, min(1.0, settings.openRouterMinSimilarity))
    self.extraInstruction = settings.openRouterExtraInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.correctionLanguage = settings.correctionLanguage
  }

  func correct(_ text: String) async throws -> String {
    lastRetryCount = 0
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return text }

    let apiKey = try resolveApiKey()
    let protected = protect(text)

    for attempt in 1...maxAttempts {
      let prompt = makePrompt(text: protected.text, attempt: attempt)
      let output = try await generate(prompt: prompt, apiKey: apiKey)
      let cleaned = cleanup(output, original: text)
      guard !cleaned.isEmpty else { throw OpenRouterError.emptyResponse }

      if !protected.placeholders.isEmpty,
         !placeholdersAllPresent(in: cleaned, placeholders: protected.placeholders)
      {
        continue
      }

      let restored = restore(cleaned, placeholders: protected.placeholders)
      if isAcceptable(original: text, candidate: restored) {
        return restored
      }
    }

    throw OpenRouterError.overRewrite
  }

  private func resolveApiKey() throws -> String {
    // Try primary keychain
    do {
      if let keyFromPrimaryKeychain = try Keychain.getPassword(service: keychainService, account: keychainAccount)?.trimmingCharacters(in: .whitespacesAndNewlines), !keyFromPrimaryKeychain.isEmpty {
        return keyFromPrimaryKeychain
      }
    } catch {
      NSLog("[TextPolish] Failed to read primary keychain: \(error)")
    }

    // Try legacy keychain
    do {
      if let keyFromLegacyKeychain = try Keychain.getPassword(service: legacyKeychainService, account: keychainAccount)?.trimmingCharacters(in: .whitespacesAndNewlines), !keyFromLegacyKeychain.isEmpty {
        if legacyKeychainService != keychainService {
          do {
            try Keychain.setPassword(keyFromLegacyKeychain, service: keychainService, account: keychainAccount, label: keychainLabel)
          } catch {
            NSLog("[TextPolish] Failed to migrate legacy keychain: \(error)")
          }
        }
        return keyFromLegacyKeychain
      }
    } catch {
      NSLog("[TextPolish] Failed to read legacy keychain: \(error)")
    }

    if let keyFromSettings, !keyFromSettings.isEmpty { return keyFromSettings }
    let env = keyFromEnv?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !env.isEmpty { return env }

    throw OpenRouterError.missingApiKey
  }

  private func makeChatCompletionsURL() throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw OpenRouterError.invalidBaseURL
    }

    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    components.path = basePath + "/chat/completions"

    guard let url = components.url else { throw OpenRouterError.invalidBaseURL }
    return url
  }

  private func generate(prompt: String, apiKey: String) async throws -> String {
    let maxNetworkAttempts = 3
    var lastError: Error?
    var retryCount = 0
    defer { lastRetryCount = retryCount }

    for attempt in 0..<maxNetworkAttempts {
      let url = try makeChatCompletionsURL()
      var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
      request.httpMethod = "POST"
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      request.setValue("TextPolish", forHTTPHeaderField: "X-Title")
      request.setValue("https://github.com/kxxil01", forHTTPHeaderField: "HTTP-Referer")

      let body = OpenRouterChatCompletionsRequest(
        model: model,
        messages: [
          .init(role: "user", content: prompt),
        ],
        temperature: 0.0,
        maxTokens: 1024
      )
      request.httpBody = try JSONEncoder().encode(body)

      do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          let error = OpenRouterError.requestFailed(-1, nil)
          lastError = error
          if attempt < maxNetworkAttempts - 1 {
            retryCount += 1
            try await Task.sleep(for: .seconds(retryDelaySeconds(attempt: attempt)))
            continue
          }
          throw error
        }

        if (200..<300).contains(http.statusCode) {
          let decoded = try JSONDecoder().decode(OpenRouterChatCompletionsResponse.self, from: data)
          let content = decoded.choices?.first?.message?.content ?? ""
          return content
        }

        let message = parseErrorMessage(data: data)
        NSLog("[TextPolish] OpenRouter HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")

        if http.statusCode == 429, attempt < maxNetworkAttempts - 1 {
          lastError = OpenRouterError.requestFailed(http.statusCode, message)
          let retryAfter = retryAfterSeconds(from: http, data: data) ?? retryDelaySeconds(attempt: attempt)
          retryCount += 1
          try await Task.sleep(for: .seconds(retryAfter))
          continue
        }

        if (500...599).contains(http.statusCode), attempt < maxNetworkAttempts - 1 {
          lastError = OpenRouterError.requestFailed(http.statusCode, message)
          retryCount += 1
          try await Task.sleep(for: .seconds(retryDelaySeconds(attempt: attempt)))
          continue
        }

        throw OpenRouterError.requestFailed(http.statusCode, message)
      } catch {
        if error is CancellationError { throw error }
        if let openRouterError = error as? OpenRouterError { throw openRouterError }

        let wrapped = OpenRouterError.requestFailed(-1, error.localizedDescription)
        lastError = wrapped
        if attempt < maxNetworkAttempts - 1 {
          retryCount += 1
          try await Task.sleep(for: .seconds(retryDelaySeconds(attempt: attempt)))
          continue
        }
        throw wrapped
      }
    }

    throw lastError ?? OpenRouterError.requestFailed(-1, nil)
  }

  private struct OpenAIErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
      let message: String?
      let code: String?
      let type: String?
    }
    let error: ErrorBody?
  }

  private func parseErrorMessage(data: Data) -> String? {
    if let decoded = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
      let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let message, !message.isEmpty { return message }
    }

    if let string = String(data: data, encoding: .utf8) {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return nil }
      return String(trimmed.prefix(240))
    }

    return nil
  }

  private func retryAfterSeconds(from response: HTTPURLResponse, data: Data) -> Double? {
    if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
       let value = Double(header) {
      return value
    }
    return extractRetryAfter(from: data)
  }

  private func extractRetryAfter(from data: Data) -> Double? {
    guard let string = String(data: data, encoding: .utf8) else { return nil }
    guard let range = string.range(of: #""retry_after"\s*:\s*"?(\d+)"?"#, options: .regularExpression) else { return nil }
    let match = string[range]
    let numberString = match.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
    if let number = Int(numberString) {
      return Double(number)
    }
    return nil
  }

  private func retryDelaySeconds(attempt: Int) -> Double {
    min(pow(2.0, Double(attempt)), 10.0)
  }

  private func makePrompt(text: String, attempt: Int) -> String {
    var instructions: [String] = [
      "You are a grammar and typo corrector.",
      "Fix only spelling, typos, grammar, and clear punctuation mistakes. Only change what is clearly wrong.",
      "Make the smallest possible edits. Do not rewrite, rephrase, translate, or change meaning, context, or tone.",
      "Match the original voice. If it is casual, keep it casual; if formal, keep it formal.",
      "Keep it human and natural; it should sound like the same person wrote it, not AI.",
      "Keep slang and abbreviations as-is. Do not make it more formal.",
      "Do not add or remove words unless required to fix an error.",
      "Do not replace commas with semicolons and do not introduce em dashes, double hyphens, or semicolons unless they already appear in the original text.",
      "Preserve formatting exactly: whitespace, line breaks, indentation, Markdown, emojis, mentions (@user, #channel), links, and code blocks.",
      "Tokens like ⟦GC_PROTECT_XXXX_0⟧ are protected placeholders and must remain unchanged.",
    ]

    if attempt > 1 {
      instructions.insert(
        "IMPORTANT: Your previous output changed the text too much. This time, keep everything identical except for the minimal characters needed to correct errors.",
        at: 2
      )
    }

    if let languageInstruction = correctionLanguage.promptInstruction {
      instructions.append(languageInstruction)
    }

    if let extraInstruction, !extraInstruction.isEmpty {
      instructions.append("Extra instruction: \(extraInstruction)")
    }

    instructions.append("Return only the corrected text. No explanations, no quotes, no code fences.")

    return (instructions + ["", "TEXT:", text]).joined(separator: "\n")
  }

  private func isAcceptable(original: String, candidate: String) -> Bool {
    guard candidate != original else { return true }
    guard newlineCount(in: candidate) == newlineCount(in: original) else { return false }
    return isSimilarEnough(original: original, candidate: candidate, minimum: minSimilarity)
  }
}

private struct OpenRouterChatCompletionsRequest: Encodable {
  struct Message: Encodable {
    let role: String
    let content: String
  }

  let model: String
  let messages: [Message]
  let temperature: Double
  let maxTokens: Int

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case temperature
    case maxTokens = "max_tokens"
  }
}

private struct OpenRouterChatCompletionsResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      let content: String?
    }
    let message: Message?
  }

  let choices: [Choice]?
}

extension OpenRouterCorrector: @unchecked Sendable {}
