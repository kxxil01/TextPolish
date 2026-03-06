import Foundation

final class OpenRouterToneAnalyzer: ToneAnalyzer, RetryReporting, DiagnosticsProviderReporting {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let keychainAccount = "openRouterApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let ownsSession: Bool
  private let retryPolicy: RetryPolicy
  private let config: ToneAnalysisConfig
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .openRouter }
  var diagnosticsModel: String { model }

  init(settings: Settings, config: ToneAnalysisConfig = .default, session: URLSession? = nil) throws {
    keyFromSettings = settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.openRouterBaseURL) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    self.baseURL = baseURL
    self.model = settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)

    // Validate model name
    if self.model.isEmpty {
      throw ToneAnalysisError.invalidModelName(settings.openRouterModel)
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
      TPLogger.log("Failed to read OpenRouter keychain: \(error)")
    }

    if let keyFromSettings, !keyFromSettings.isEmpty { return keyFromSettings }
    let env = keyFromEnv?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !env.isEmpty { return env }

    throw ToneAnalysisError.missingApiKey("OpenRouter")
  }

  private func makeChatCompletionsURL() throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw ToneAnalysisError.invalidBaseURL
    }
    components.path = OpenRouterEndpointPath.chatCompletionsPath(basePath: components.path)

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
        request.setValue("TextPolish", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/kxxil01", forHTTPHeaderField: "HTTP-Referer")

        let body = OpenRouterToneRequest(
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
          let decoded = try JSONDecoder().decode(OpenRouterToneResponse.self, from: data)
          let content = decoded.choices?.first?.message?.content ?? ""

          // Check if response is empty
          guard !content.isEmpty else {
            throw ToneAnalysisError.emptyResponse
          }
          return content
        }

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

        let message = ErrorLogSanitizer.sanitize(parseErrorMessage(data: data))
        TPLogger.log("OpenRouter Tone HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
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
      let message = ErrorLogSanitizer.sanitize(decoded.error?.message)
      if let message, !message.isEmpty { return message }
    }

    if let string = String(data: data, encoding: .utf8) {
      return ErrorLogSanitizer.sanitize(string)
    }

    return nil
  }

  private func makePrompt(text: String) -> String {
    ToneAnalysisPromptBuilder.makePrompt(text: text)
  }
}

private struct OpenRouterToneRequest: Encodable {
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

private struct OpenRouterToneResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      let content: String?
    }
    let message: Message?
  }

  let choices: [Choice]?
}

extension OpenRouterToneAnalyzer: @unchecked Sendable {}
