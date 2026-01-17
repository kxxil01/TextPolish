import Foundation

final class OpenRouterToneAnalyzer: ToneAnalyzer {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.kxxil01.TextPolish"
  private let keychainAccount = "openRouterApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let config: ToneAnalysisConfig

  init(settings: Settings, config: ToneAnalysisConfig = .default) throws {
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
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    self.session = URLSession(configuration: configuration)
    self.config = config
  }

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
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
    let keyFromPrimaryKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccount))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromPrimaryKeychain.isEmpty { return keyFromPrimaryKeychain }

    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccount))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromLegacyKeychain.isEmpty { return keyFromLegacyKeychain }

    if let keyFromSettings, !keyFromSettings.isEmpty { return keyFromSettings }
    let env = keyFromEnv?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !env.isEmpty { return env }

    throw ToneAnalysisError.missingApiKey("OpenRouter")
  }

  private func makeChatCompletionsURL() throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    components.path = basePath + "/chat/completions"

    guard let url = components.url else { throw ToneAnalysisError.invalidBaseURL }
    return url
  }

  private func generate(prompt: String, apiKey: String) async throws -> String {
    // Try up to 3 times with rate limit backoff
    for attempt in 0..<3 {
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

        // Handle rate limiting with exponential backoff
        if http.statusCode == 429 {
          let retryAfter = extractRetryAfter(from: data) ?? Double(min(2 * (attempt + 1), 10))
          try await Task.sleep(for: .seconds(retryAfter))
          // Continue to next attempt
          continue
        }

        let message = parseErrorMessage(data: data)
        NSLog("[TextPolish] OpenRouter Tone HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
        throw ToneAnalysisError.requestFailed(http.statusCode, message)
      } catch {
        // If it's the last attempt, throw the error
        if attempt == 2 {
          throw error
        }
        // For other errors on non-last attempts, continue
        continue
      }
    }

    throw ToneAnalysisError.requestFailed(-1, nil)
  }

  private func extractRetryAfter(from data: Data) -> Double? {
    guard let string = String(data: data, encoding: .utf8) else { return nil }
    guard let range = string.range(of: #"retry_after"\s*:\s*(\d+)"#, options: .regularExpression) else { return nil }
    let match = string[range]
    let numberString = match.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
    if let number = Int(numberString) {
      return Double(number)
    }
    return nil
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
