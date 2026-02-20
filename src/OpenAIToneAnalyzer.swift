import Foundation

final class OpenAIToneAnalyzer: ToneAnalyzer, RetryReporting, DiagnosticsProviderReporting {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let keychainAccount = "openAIApiKey"
  private let keychainLabel = "TextPolish — OpenAI API Key"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let ownsSession: Bool
  private let retryPolicy: RetryPolicy
  private let config: ToneAnalysisConfig
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .openAI }
  var diagnosticsModel: String { model }

  init(settings: Settings, config: ToneAnalysisConfig = .default, session: URLSession? = nil) throws {
    keyFromSettings = settings.openAIApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.openAIBaseURL) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    self.baseURL = baseURL
    self.model = settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)

    // Validate model name
    if self.model.isEmpty {
      throw ToneAnalysisError.invalidModelName(settings.openAIModel)
    }

    self.timeoutSeconds = settings.requestTimeoutSeconds
    if let session {
      self.session = session
      self.ownsSession = false
    } else {
      let configuration = URLSessionConfiguration.default
      configuration.waitsForConnectivity = true
      configuration.timeoutIntervalForRequest = timeoutSeconds
      configuration.timeoutIntervalForResource = timeoutSeconds
      self.session = URLSession(configuration: configuration)
      self.ownsSession = true
    }
    self.retryPolicy = RetryPolicy()
    self.config = config
  }

  deinit {
    if ownsSession {
      session.invalidateAndCancel()
    }
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

    throw ToneAnalysisError.missingApiKey("OpenAI")
  }

  private func makeChatCompletionsURL() throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    if basePath.hasSuffix("/chat/completions") {
      basePath.removeLast("/chat/completions".count)
    }

    if basePath.isEmpty {
      components.path = "/chat/completions"
    } else {
      components.path = basePath + "/chat/completions"
    }

    guard let url = components.url else { throw ToneAnalysisError.invalidBaseURL }
    return url
  }

  private func generate(prompt: String, apiKey: String) async throws -> String {
    var retryCount = 0
    defer { lastRetryCount = retryCount }

    for attempt in 0..<retryPolicy.maxNetworkAttempts {
      do {
        let url = try makeChatCompletionsURL()
        var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = OpenAIToneRequest(
          model: model,
          messages: [
            .init(role: "user", content: prompt),
          ],
          temperature: 0.0,
          maxTokens: config.maxOutputTokens
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          throw ToneAnalysisError.requestFailed(-1, nil)
        }

        if (200..<300).contains(http.statusCode) {
          let decoded = try JSONDecoder().decode(OpenAIToneResponse.self, from: data)
          let content = decoded.choices?.first?.message?.content ?? ""
          guard !content.isEmpty else { throw ToneAnalysisError.emptyResponse }
          return content
        }

        let message = parseErrorMessage(data: data)
        NSLog("[TextPolish] OpenAI Tone HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")

        let canRetry = attempt < retryPolicy.maxNetworkAttempts - 1
        if canRetry && (http.statusCode == 429 || (500...599).contains(http.statusCode)) {
          let retryAfterRaw = http.statusCode == 429
            ? (RetryAfterParser.retryAfterSeconds(from: http, data: data)
                ?? retryPolicy.retryDelaySeconds(attempt: attempt))
            : retryPolicy.retryDelaySeconds(attempt: attempt)
          let retryAfter = http.statusCode == 429
            ? retryPolicy.clampedRateLimitBackoff(retryAfterRaw)
            : retryAfterRaw
          retryCount += 1
          try await Task.sleep(for: .seconds(retryAfter))
          continue
        }

        throw ToneAnalysisError.requestFailed(http.statusCode, message)
      } catch {
        if error is CancellationError { throw error }
        if case ToneAnalysisError.requestFailed(let status, _) = error,
           (400..<500).contains(status), status != 429
        {
          throw error
        }
        if attempt == retryPolicy.maxNetworkAttempts - 1 {
          throw error
        }
        retryCount += 1
        try await Task.sleep(for: .seconds(retryPolicy.retryDelaySeconds(attempt: attempt)))
      }
    }

    throw ToneAnalysisError.requestFailed(-1, nil)
  }

  private struct OpenAIErrorEnvelopeTone: Decodable {
    struct ErrorBody: Decodable {
      let message: String?
      let code: String?
      let type: String?
    }
    let error: ErrorBody?
  }

  private func parseErrorMessage(data: Data) -> String? {
    if let decoded = try? JSONDecoder().decode(OpenAIErrorEnvelopeTone.self, from: data) {
      let message = ErrorLogSanitizer.sanitize(decoded.error?.message)
      if let message, !message.isEmpty { return message }
    }

    if let string = String(data: data, encoding: .utf8) {
      return ErrorLogSanitizer.sanitize(string)
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

private struct OpenAIToneRequest: Encodable {
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

private struct OpenAIToneResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      let content: String?
    }
    let message: Message?
  }

  let choices: [Choice]?
}

// Safety: `lastRetryCount` is only mutated during one analysis call at a time.
// Controllers own a single analyzer instance and do not issue concurrent requests.
extension OpenAIToneAnalyzer: @unchecked Sendable {}
