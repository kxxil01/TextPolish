import Foundation

final class AnthropicToneAnalyzer: ToneAnalyzer, RetryReporting, DiagnosticsProviderReporting {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let keychainAccount = "anthropicApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let ownsSession: Bool
  private let retryPolicy: RetryPolicy
  private let config: ToneAnalysisConfig
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .anthropic }
  var diagnosticsModel: String { model }

  init(settings: Settings, config: ToneAnalysisConfig = .default, session: URLSession? = nil) throws {
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
    let trimmed = try config.validatedInputText(text)
    let apiKey = try resolveApiKey()
    let prompt = makePrompt(text: trimmed)
    let output = try await generate(prompt: prompt, apiKey: apiKey)
    if PromptGuardrails.detectRefusal(output) {
      throw ToneAnalysisError.invalidResponse("AI refused to analyze the text")
    }

    return try ToneAnalysisJSONParser.parseResponse(output)
  }

  private func resolveApiKey() throws -> String {
    do {
      if let key = try Keychain.getConfiguredPassword(
        primaryService: keychainService,
        account: keychainAccount
      ), !key.isEmpty {
        return key
      }
    } catch {
      TPLogger.log("Failed to read Anthropic keychain: \(error)")
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

  private func generate(prompt: PromptPair, apiKey: String) async throws -> String {
    var retryCount = 0
    defer { lastRetryCount = retryCount }

    for attempt in 0..<retryPolicy.maxNetworkAttempts {
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
          system: prompt.system,
          messages: [
            .init(role: "user", content: prompt.user),
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
          guard !content.isEmpty else { throw ToneAnalysisError.emptyResponse }
          return content
        }

        let message = parseErrorMessage(data: data)
        TPLogger.log("Anthropic Tone HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")

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

  private struct AnthropicAPIErrorEnvelopeTone: Decodable {
    struct ErrorBody: Decodable {
      let message: String?
      let type: String?
    }
    let error: ErrorBody?
  }

  private func parseErrorMessage(data: Data) -> String? {
    if let decoded = try? JSONDecoder().decode(AnthropicAPIErrorEnvelopeTone.self, from: data) {
      let message = ErrorLogSanitizer.sanitize(decoded.error?.message)
      if let message, !message.isEmpty { return message }
    }

    if let string = String(data: data, encoding: .utf8) {
      return ErrorLogSanitizer.sanitize(string)
    }

    return nil
  }

  private func makePrompt(text: String) -> PromptPair {
    ToneAnalysisPromptBuilder.makePrompt(text: text)
  }
}

private struct AnthropicToneRequest: Encodable {
  struct Message: Encodable {
    let role: String
    let content: String
  }

  let model: String
  let maxTokens: Int
  let system: String?
  let messages: [Message]

  enum CodingKeys: String, CodingKey {
    case model
    case maxTokens = "max_tokens"
    case system
    case messages
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(model, forKey: .model)
    try container.encode(maxTokens, forKey: .maxTokens)
    try container.encodeIfPresent(system, forKey: .system)
    try container.encode(messages, forKey: .messages)
  }
}

private struct AnthropicToneResponse: Decodable {
  struct ContentBlock: Decodable {
    let type: String
    let text: String?
  }

  let content: [ContentBlock]
}

// Safety: `lastRetryCount` is only mutated during one analysis call at a time.
// Controllers own a single analyzer instance and do not issue concurrent requests.
extension AnthropicToneAnalyzer: @unchecked Sendable {}
