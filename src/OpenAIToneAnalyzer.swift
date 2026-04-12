import Foundation

final class OpenAIToneAnalyzer: ToneAnalyzer, RetryReporting, DiagnosticsProviderReporting {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let keychainAccount = "openAIApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let ownsSession: Bool
  private let retryPolicy: RetryPolicy
  private let config: ToneAnalysisConfig
  private(set) var lastRetryCount: Int = 0
  private var lastRateLimitRetryAfterSeconds: Double?

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
      TPLogger.log("Failed to read OpenAI keychain: \(error)")
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

  private func generate(prompt: PromptPair, apiKey: String) async throws -> String {
    var retryCount = 0
    lastRateLimitRetryAfterSeconds = nil
    defer { lastRetryCount = retryCount }
    let preferredUsesMaxCompletionTokens = OpenAITokenPolicy.usesMaxCompletionTokens(model: model)

    for attempt in 0..<retryPolicy.maxNetworkAttempts {
      do {
        do {
          return try await sendRequest(
            prompt: prompt,
            apiKey: apiKey,
            useMaxCompletionTokens: preferredUsesMaxCompletionTokens
          )
        } catch let preferredError as ToneAnalysisError {
          if case .requestFailed(let status, let message) = preferredError,
             status == 400,
             OpenAITokenPolicy.isTokenParameterError(message: message)
          {
            return try await sendRequest(
              prompt: prompt,
              apiKey: apiKey,
              useMaxCompletionTokens: !preferredUsesMaxCompletionTokens
            )
          }
          throw preferredError
        }
      } catch {
        if error is CancellationError { throw error }
        if case ToneAnalysisError.requestFailed(let status, _) = error {
          let canRetry = attempt < retryPolicy.maxNetworkAttempts - 1
          if canRetry && status == 429 {
            retryCount += 1
            let retryAfter = retryPolicy.clampedRateLimitBackoff(
              lastRateLimitRetryAfterSeconds ?? retryPolicy.retryDelaySeconds(attempt: attempt)
            )
            lastRateLimitRetryAfterSeconds = nil
            try await Task.sleep(for: .seconds(retryAfter))
            continue
          }
          if canRetry && (500...599).contains(status) {
            retryCount += 1
            try await Task.sleep(for: .seconds(retryPolicy.retryDelaySeconds(attempt: attempt)))
            continue
          }
        }
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

  private func sendRequest(
    prompt: PromptPair,
    apiKey: String,
    useMaxCompletionTokens: Bool
  ) async throws -> String {
    let url = try makeChatCompletionsURL()
    var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
    request.httpMethod = "POST"
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let body = OpenAIToneRequest(
      model: model,
      messages: [
        .init(role: "system", content: prompt.system),
        .init(role: "user", content: prompt.user),
      ],
      temperature: 0.0,
      maxTokens: config.maxOutputTokens,
      useMaxCompletionTokens: useMaxCompletionTokens
    )
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ToneAnalysisError.requestFailed(-1, nil)
    }

    if (200..<300).contains(http.statusCode) {
      lastRateLimitRetryAfterSeconds = nil
      let decoded = try JSONDecoder().decode(OpenAIToneResponse.self, from: data)
      let content = decoded.choices?.first?.message?.content ?? ""
      guard !content.isEmpty else { throw ToneAnalysisError.emptyResponse }
      return content
    }

    let message = parseErrorMessage(data: data)
    lastRateLimitRetryAfterSeconds =
      http.statusCode == 429 ? RetryAfterParser.retryAfterSeconds(from: http, data: data) : nil
    TPLogger.log("OpenAI Tone HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
    throw ToneAnalysisError.requestFailed(http.statusCode, message)
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

  private func makePrompt(text: String) -> PromptPair {
    ToneAnalysisPromptBuilder.makePrompt(text: text)
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
  let useMaxCompletionTokens: Bool

  init(
    model: String,
    messages: [Message],
    temperature: Double,
    maxTokens: Int,
    useMaxCompletionTokens: Bool? = nil
  ) {
    self.model = model
    self.messages = messages
    self.temperature = temperature
    self.maxTokens = maxTokens
    self.useMaxCompletionTokens = useMaxCompletionTokens ?? OpenAITokenPolicy.usesMaxCompletionTokens(model: model)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(model, forKey: .model)
    try container.encode(messages, forKey: .messages)
    try container.encode(temperature, forKey: .temperature)
    if useMaxCompletionTokens {
      try container.encode(maxTokens, forKey: .maxCompletionTokens)
    } else {
      try container.encode(maxTokens, forKey: .maxTokens)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case model
    case messages
    case temperature
    case maxTokens = "max_tokens"
    case maxCompletionTokens = "max_completion_tokens"
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
