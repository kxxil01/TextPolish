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
          return "OpenRouter payment required (402) — add credits or use a free model "
            + "(Provider → Set OpenRouter Model… / Detect OpenRouter Model…)"
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
        return "OpenRouter changed too much and was rejected. Lower OpenRouter Min Similarity or simplify extra instruction."
      }
    }
  }

  // MARK: - TextProcessor Requirements

  let minSimilarity: Double

  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let keychainAccount = "openRouterApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let maxAttempts: Int
  private let retryPolicy: RetryPolicy
  private let extraInstruction: String?
  private let protectedTerms: [String]
  private let correctionLanguage: Settings.CorrectionLanguage
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .openRouter }
  var diagnosticsModel: String { model }

  init(settings: Settings) throws {
    keyFromSettings = settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
    keychainService = Keychain.primaryService(bundleIdentifier: Bundle.main.bundleIdentifier)
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
    self.retryPolicy = RetryPolicy(maxNetworkAttempts: 2, maxRateLimitBackoffSeconds: 12)
    self.minSimilarity = max(0.0, min(1.0, settings.openRouterMinSimilarity))
    self.extraInstruction = PromptGuardrails.sanitizeExtraInstruction(settings.openRouterExtraInstruction)
    self.protectedTerms = settings.protectedTerms
    self.correctionLanguage = settings.correctionLanguage
  }

  deinit {
    session.invalidateAndCancel()
  }

  func correct(_ text: String) async throws -> String {
    try await correct(text, style: .minimal)
  }

  func correct(_ text: String, style: CorrectionStyle) async throws -> String {
    lastRetryCount = 0
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return text }
    try PromptGuardrails.validateInputLength(text, maxLength: PromptGuardrails.maxCorrectionInputLength)

    let apiKey = try resolveApiKey()
    let protected = protect(text, terms: protectedTerms)

    var retryReason: CorrectionRetryReason?
    for attempt in 1...maxAttempts {
      let prompt = CorrectionPromptBuilder.makePrompt(
        text: protected.text,
        retryReason: retryReason,
        correctionLanguage: correctionLanguage,
        extraInstruction: extraInstruction,
        style: style
      )
      let output = try await generate(prompt: prompt, apiKey: apiKey)
      let cleaned = cleanup(output, original: text)
      guard !cleaned.isEmpty else { throw OpenRouterError.emptyResponse }
      if PromptGuardrails.detectRefusal(cleaned) {
        retryReason = .refusal
        TPLogger.log("OpenRouter attempt \(attempt)/\(maxAttempts) rejected: refusal")
        continue
      }
      if !PromptGuardrails.validateOutputLength(input: text, output: cleaned) {
        retryReason = .outputTooLong
        TPLogger.log("OpenRouter attempt \(attempt)/\(maxAttempts) rejected: outputTooLong")
        continue
      }

      if !protected.placeholders.isEmpty,
         !placeholdersAllPresent(in: cleaned, placeholders: protected.placeholders)
      {
        retryReason = .placeholdersMissing
        TPLogger.log("OpenRouter attempt \(attempt)/\(maxAttempts) rejected: placeholdersMissing")
        continue
      }

      let restored = restore(cleaned, placeholders: protected.placeholders)
      let minimum = style.minimumSimilarity(configured: minSimilarity)
      guard let rejection = rejectionReason(
        original: text,
        candidate: restored,
        style: style,
        minimumSimilarity: minimum
      ) else {
        return restored
      }
      retryReason = rejection
      let summary = rejectionSummary(original: text, candidate: restored, minimumSimilarity: minimum)
      TPLogger.log("OpenRouter attempt \(attempt)/\(maxAttempts) rejected: \(rejection), \(summary)")
    }

    throw OpenRouterError.overRewrite
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

    throw OpenRouterError.missingApiKey
  }

  private func makeChatCompletionsURL() throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw OpenRouterError.invalidBaseURL
    }
    components.path = OpenRouterEndpointPath.chatCompletionsPath(basePath: components.path)

    guard let url = components.url else { throw OpenRouterError.invalidBaseURL }
    return url
  }

  private func generate(prompt: PromptPair, apiKey: String) async throws -> String {
    var retryCount = 0
    let incrementRetryCount = { retryCount += 1 }
    defer { lastRetryCount = retryCount }

    return try await retryPolicy.performWithBackoff(
      maxAttempts: retryPolicy.maxNetworkAttempts,
      onRetry: incrementRetryCount
    ) { attempt, isLastAttempt in
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
          .init(role: "system", content: prompt.system),
          .init(role: "user", content: prompt.user),
        ],
        temperature: 0.0,
        maxTokens: CorrectionPromptBuilder.maxOutputTokens(for: prompt.user)
      )
      request.httpBody = try JSONEncoder().encode(body)

      do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          let error = OpenRouterError.requestFailed(-1, nil)
          if isLastAttempt {
            return .fail(error)
          }
          return .retry(after: retryPolicy.retryDelaySeconds(attempt: attempt), lastError: error)
        }

        if (200..<300).contains(http.statusCode) {
          let decoded = try JSONDecoder().decode(OpenRouterChatCompletionsResponse.self, from: data)
          UsageLedger.shared.record(provider: self.diagnosticsProvider, model: self.model, responseBody: data)
          let content = decoded.choices?.first?.message?.content ?? ""
          return .success(content)
        }

        let message = ErrorLogSanitizer.sanitize(parseErrorMessage(data: data))
        TPLogger.log("OpenRouter HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")

        let requestError = OpenRouterError.requestFailed(http.statusCode, message)

        if http.statusCode == 429, !isLastAttempt {
          let requestedRetryAfter = RetryAfterParser.retryAfterSeconds(from: http, data: data)
            ?? retryPolicy.retryDelaySeconds(attempt: attempt)
          let retryAfter = retryPolicy.clampedRateLimitBackoff(requestedRetryAfter)
          return .retry(after: retryAfter, lastError: requestError)
        }

        if (500...599).contains(http.statusCode), !isLastAttempt {
          return .retry(after: retryPolicy.retryDelaySeconds(attempt: attempt), lastError: requestError)
        }

        return .fail(requestError)
      } catch {
        if error is CancellationError { throw error }
        if let openRouterError = error as? OpenRouterError {
          return .fail(openRouterError)
        }

        let sanitizedErrorDescription = ErrorLogSanitizer.sanitize(error.localizedDescription)
        let wrapped = OpenRouterError.requestFailed(-1, sanitizedErrorDescription)
        if isLastAttempt {
          return .fail(wrapped)
        }
        return .retry(after: retryPolicy.retryDelaySeconds(attempt: attempt), lastError: wrapped)
      }
    }
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

extension OpenRouterCorrector: TextGenerating, MessageExplaining {
  func generateText(_ prompt: PromptPair) async throws -> String {
    try await generate(prompt: prompt, apiKey: try resolveApiKey())
  }
}

extension OpenRouterCorrector: ChangeExplaining {
  func explainChanges(original: String, polished: String) async throws -> [String] {
    let output = try await generate(
      prompt: ChangeExplanationPrompt.make(original: original, polished: polished),
      apiKey: try resolveApiKey()
    )
    return ChangeExplanationPrompt.parse(output)
  }
}
