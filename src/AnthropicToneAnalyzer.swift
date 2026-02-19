import Foundation

final class AnthropicToneAnalyzer: ToneAnalyzer, RetryReporting, DiagnosticsProviderReporting {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let keychainAccount = "anthropicApiKey"
  private let keychainLabel = "TextPolish — Anthropic API Key"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let maxRateLimitBackoffSeconds: Double
  private let config: ToneAnalysisConfig
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .anthropic }
  var diagnosticsModel: String { model }

  init(settings: Settings, config: ToneAnalysisConfig = .default) throws {
    keyFromSettings = settings.anthropicApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.anthropicBaseURL) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    self.baseURL = baseURL
    self.model = settings.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines)

    // Validate model name
    if self.model.isEmpty {
      throw ToneAnalysisError.invalidModelName(settings.anthropicModel)
    }

    self.timeoutSeconds = settings.requestTimeoutSeconds
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    self.session = URLSession(configuration: configuration)
    self.maxRateLimitBackoffSeconds = 12
    self.config = config
  }

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    lastRetryCount = 0
    // Validate original text length before trimming
    guard text.count >= config.minTextLength else { throw ToneAnalysisError.textTooShort }
    guard text.count <= config.maxTextLength else { throw ToneAnalysisError.textTooLong }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let apiKey = try resolveApiKey()
    let prompt = makePrompt(text: trimmed)
    let output = try await generate(prompt: prompt, apiKey: apiKey)

    return try ToneAnalysisJSONParser.parseResponse(output)
  }

  private func resolveApiKey() throws -> String {
    // Try primary keychain
    do {
      if let keyFromPrimaryKeychain = try Keychain.getPassword(service: keychainService, account: keychainAccount)?
        .trimmingCharacters(in: .whitespacesAndNewlines), !keyFromPrimaryKeychain.isEmpty {
        return keyFromPrimaryKeychain
      }
    } catch {
      NSLog("[TextPolish] Failed to read primary keychain: \(error)")
    }

    // Try legacy keychain and migrate
    do {
      if let keyFromLegacyKeychain = try Keychain.getPassword(service: legacyKeychainService, account: keychainAccount)?
        .trimmingCharacters(in: .whitespacesAndNewlines), !keyFromLegacyKeychain.isEmpty {
        if legacyKeychainService != keychainService {
          do {
            try Keychain.setPassword(
              keyFromLegacyKeychain,
              service: keychainService,
              account: keychainAccount,
              label: keychainLabel
            )
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

    throw ToneAnalysisError.missingApiKey("Anthropic")
  }

  private func makeMessagesURL() throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    if basePath.hasSuffix("/v1/messages") {
      basePath.removeLast("/v1/messages".count)
    } else if basePath.hasSuffix("/v1") {
      basePath.removeLast("/v1".count)
    }

    if basePath.isEmpty {
      components.path = "/v1/messages"
    } else {
      components.path = basePath + "/v1/messages"
    }

    guard let url = components.url else { throw ToneAnalysisError.invalidBaseURL }
    return url
  }

  private func generate(prompt: String, apiKey: String) async throws -> String {
    // Try up to 3 times with rate limit backoff
    var retryCount = 0
    defer { lastRetryCount = retryCount }
    for attempt in 0..<3 {
      do {
        let url = try makeMessagesURL()
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = AnthropicToneRequest(
          model: model,
          maxTokens: config.maxOutputTokens,
          messages: [
            .init(role: "user", content: prompt),
          ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          throw ToneAnalysisError.requestFailed(-1, nil)
        }

        if (200..<300).contains(http.statusCode) {
          let decoded = try JSONDecoder().decode(AnthropicToneResponse.self, from: data)
          let content = decoded.content.first(where: { $0.type == "text" })?.text ?? ""

          // Check if response is empty
          guard !content.isEmpty else {
            throw ToneAnalysisError.emptyResponse
          }
          return content
        }

        // Handle rate limiting with exponential backoff
        if http.statusCode == 429 {
          let requestedRetryAfter = extractRetryAfter(from: data) ?? Double(min(2 * (attempt + 1), 10))
          let retryAfter = clampedRateLimitBackoff(requestedRetryAfter)
          retryCount += 1
          try await Task.sleep(for: .seconds(retryAfter))
          // Continue to next attempt
          continue
        }

        let message = parseErrorMessage(data: data)
        NSLog("[TextPolish] Anthropic Tone HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
        throw ToneAnalysisError.requestFailed(http.statusCode, message)
      } catch {
        if error is CancellationError {
          throw error
        }
        if case ToneAnalysisError.requestFailed(let status, _) = error,
           (400..<500).contains(status)
        {
          throw error
        }
        // If it's the last attempt, throw the error
        if attempt == 2 {
          throw error
        }
        // For other errors on non-last attempts, continue
        retryCount += 1
        try await Task.sleep(for: .seconds(1))
        continue
      }
    }

    throw ToneAnalysisError.requestFailed(-1, nil)
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

  private func clampedRateLimitBackoff(_ requested: Double) -> Double {
    let sanitized = requested.isFinite ? requested : 1
    return min(max(1, sanitized), maxRateLimitBackoffSeconds)
  }

  private struct AnthropicAPIErrorEnvelopeTone: Decodable {
    struct ErrorBody: Decodable {
      let message: String?
      let type: String?
    }
    let error: ErrorBody?
  }

  private func parseErrorMessage(data: Data) -> String? {
    if let decoded = try? JSONDecoder().decode(AnthropicAPIErrorEnvelopeTone.self, from: data) {
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

  private func makePrompt(text: String) -> String {
    let toneOptions = DetectedTone.allCases.map(\.rawValue).joined(separator: ", ")
    let sentimentOptions = Sentiment.allCases.map(\.rawValue).joined(separator: ", ")
    let formalityOptions = FormalityLevel.allCases.map(\.rawValue).joined(separator: ", ")

    return """
    Analyze the tone of the following text. Return a JSON object with exactly these fields:
    - "tone": one of [\(toneOptions)]
    - "sentiment": one of [\(sentimentOptions)]
    - "formality": one of [\(formalityOptions)]
    - "explanation": a brief 1-2 sentence explanation of why you classified it this way

    Respond with ONLY the JSON object, no other text, no code fences.

    TEXT:
    \(text)
    """
  }
}

private struct AnthropicToneRequest: Encodable {
  struct Message: Encodable {
    let role: String
    let content: String
  }

  let model: String
  let maxTokens: Int
  let messages: [Message]

  enum CodingKeys: String, CodingKey {
    case model
    case maxTokens = "max_tokens"
    case messages
  }
}

private struct AnthropicToneResponse: Decodable {
  struct ContentBlock: Decodable {
    let type: String
    let text: String?
  }

  let content: [ContentBlock]
}

extension AnthropicToneAnalyzer: @unchecked Sendable {}
