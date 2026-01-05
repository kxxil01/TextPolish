import Foundation

final class OpenRouterToneAnalyzer: ToneAnalyzer {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let keychainAccount = "openRouterApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double

  init(settings: Settings) throws {
    keyFromSettings = settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.openRouterBaseURL) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    self.baseURL = baseURL
    self.model = settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
    self.timeoutSeconds = settings.requestTimeoutSeconds
  }

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 5 else { throw ToneAnalysisError.textTooShort }

    let apiKey = try resolveApiKey()
    let prompt = makePrompt(text: trimmed)
    let output = try await generate(prompt: prompt, apiKey: apiKey)

    return try parseResponse(output)
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
      maxTokens: 512
    )
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ToneAnalysisError.requestFailed(-1, nil)
    }

    if (200..<300).contains(http.statusCode) {
      let decoded = try JSONDecoder().decode(OpenRouterToneResponse.self, from: data)
      let content = decoded.choices?.first?.message?.content ?? ""
      return content
    }

    let message = parseErrorMessage(data: data)
    NSLog("[TextPolish] OpenRouter Tone HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
    throw ToneAnalysisError.requestFailed(http.statusCode, message)
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

  private func parseResponse(_ response: String) throws -> ToneAnalysisResult {
    var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove markdown code fences if present
    if cleaned.hasPrefix("```json") {
      cleaned = String(cleaned.dropFirst(7))
    } else if cleaned.hasPrefix("```") {
      cleaned = String(cleaned.dropFirst(3))
    }
    if cleaned.hasSuffix("```") {
      cleaned = String(cleaned.dropLast(3))
    }
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !cleaned.isEmpty else { throw ToneAnalysisError.emptyResponse }

    guard let data = cleaned.data(using: .utf8) else {
      throw ToneAnalysisError.invalidResponse("Could not convert to data")
    }

    do {
      let parsed = try JSONDecoder().decode(ToneAnalysisJSON.self, from: data)
      return ToneAnalysisResult(
        tone: parsed.tone,
        sentiment: parsed.sentiment,
        formality: parsed.formality,
        explanation: parsed.explanation
      )
    } catch {
      throw ToneAnalysisError.invalidResponse(error.localizedDescription)
    }
  }
}

private struct ToneAnalysisJSON: Decodable {
  let tone: DetectedTone
  let sentiment: Sentiment
  let formality: FormalityLevel
  let explanation: String
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
