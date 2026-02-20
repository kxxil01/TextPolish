import Foundation

final class OpenAICorrector: GrammarCorrector, TextProcessor, RetryReporting, DiagnosticsProviderReporting {
  enum OpenAIError: Error, LocalizedError {
    case missingApiKey
    case invalidBaseURL
    case invalidModel
    case requestFailed(Int, String?)
    case emptyResponse
    case overRewrite

    var errorDescription: String? {
      switch self {
      case .missingApiKey:
        return "Missing OpenAI API key"
      case .invalidBaseURL:
        return "Invalid OpenAI base URL"
      case .invalidModel:
        return "Invalid OpenAI model"
      case .requestFailed(let status, let message):
        if status == 401 {
          return "OpenAI unauthorized (401) — check API key"
        }
        if status == 402 {
          return "OpenAI payment required (402) — check billing"
        }
        if status == 429 {
          return "OpenAI rate limited (429) — try again later"
        }
        if let message, !message.isEmpty {
          return "OpenAI request failed (\(status)): \(message)"
        }
        return "OpenAI request failed (\(status))"
      case .emptyResponse:
        return "OpenAI returned no text"
      case .overRewrite:
        return "OpenAI rewrote too much (try again or adjust model)"
      }
    }
  }

  // MARK: - TextProcessor Requirements

  let minSimilarity: Double


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
  private let maxAttempts: Int
  private let retryPolicy: RetryPolicy
  private let extraInstruction: String?
  private let correctionLanguage: Settings.CorrectionLanguage
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .openAI }
  var diagnosticsModel: String { model }

  init(settings: Settings) throws {
    keyFromSettings = settings.openAIApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.openAIBaseURL) else { throw OpenAIError.invalidBaseURL }

    self.baseURL = baseURL
    let trimmedModel = settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
    self.model = trimmedModel
    guard !trimmedModel.isEmpty else { throw OpenAIError.invalidModel }
    self.timeoutSeconds = settings.requestTimeoutSeconds
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    self.session = URLSession(configuration: configuration)
    self.maxAttempts = max(1, settings.openAIMaxAttempts)
    self.retryPolicy = RetryPolicy()
    self.minSimilarity = max(0.0, min(1.0, settings.openAIMinSimilarity))
    self.extraInstruction = settings.openAIExtraInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.correctionLanguage = settings.correctionLanguage
  }

  deinit {
    session.invalidateAndCancel()
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
      guard !cleaned.isEmpty else { throw OpenAIError.emptyResponse }

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

    throw OpenAIError.overRewrite
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

    throw OpenAIError.missingApiKey
  }

  private func makeChatCompletionsURL() throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw OpenAIError.invalidBaseURL
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

    guard let url = components.url else { throw OpenAIError.invalidBaseURL }
    return url
  }

  private func generate(prompt: String, apiKey: String) async throws -> String {
    let maxNetworkAttempts = retryPolicy.maxNetworkAttempts
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

      let body = OpenAIChatCompletionsRequest(
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
          let error = OpenAIError.requestFailed(-1, nil)
          lastError = error
          if attempt < maxNetworkAttempts - 1 {
            retryCount += 1
            try await Task.sleep(for: .seconds(retryPolicy.retryDelaySeconds(attempt: attempt)))
            continue
          }
          throw error
        }

        if (200..<300).contains(http.statusCode) {
          let decoded = try JSONDecoder().decode(OpenAIChatCompletionsResponse.self, from: data)
          let content = decoded.choices?.first?.message?.content ?? ""
          return content
        }

        let message = parseErrorMessage(data: data)
        NSLog("[TextPolish] OpenAI HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")

        if http.statusCode == 429, attempt < maxNetworkAttempts - 1 {
          lastError = OpenAIError.requestFailed(http.statusCode, message)
          let requestedRetryAfter = RetryAfterParser.retryAfterSeconds(from: http, data: data)
            ?? retryPolicy.retryDelaySeconds(attempt: attempt)
          let retryAfter = retryPolicy.clampedRateLimitBackoff(requestedRetryAfter)
          retryCount += 1
          try await Task.sleep(for: .seconds(retryAfter))
          continue
        }

        if (500...599).contains(http.statusCode), attempt < maxNetworkAttempts - 1 {
          lastError = OpenAIError.requestFailed(http.statusCode, message)
          retryCount += 1
          try await Task.sleep(for: .seconds(retryPolicy.retryDelaySeconds(attempt: attempt)))
          continue
        }

        throw OpenAIError.requestFailed(http.statusCode, message)
      } catch {
        if error is CancellationError { throw error }
        if let openAIError = error as? OpenAIError { throw openAIError }

        let wrapped = OpenAIError.requestFailed(-1, error.localizedDescription)
        lastError = wrapped
        if attempt < maxNetworkAttempts - 1 {
          retryCount += 1
          try await Task.sleep(for: .seconds(retryPolicy.retryDelaySeconds(attempt: attempt)))
          continue
        }
        throw wrapped
      }
    }

    throw lastError ?? OpenAIError.requestFailed(-1, nil)
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

private struct OpenAIChatCompletionsRequest: Encodable {
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

private struct OpenAIChatCompletionsResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable {
      let content: String?
    }
    let message: Message?
  }

  let choices: [Choice]?
}

// Safety: `lastRetryCount` is mutated only inside a single in-flight request path.
// `CorrectionController` serializes execution (`isRunning`) so this type is not used concurrently.
extension OpenAICorrector: @unchecked Sendable {}
