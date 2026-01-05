import Foundation

final class GeminiToneAnalyzer: ToneAnalyzer {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.kxxil01.TextPolish"
  private let keychainAccount = "geminiApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let config: ToneAnalysisConfig

  init(settings: Settings, config: ToneAnalysisConfig = .default) throws {
    keyFromSettings = settings.geminiApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv =
      ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ??
      ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.geminiBaseURL) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    self.baseURL = baseURL
    let rawModel = settings.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if rawModel.hasPrefix("models/") {
      self.model = String(rawModel.dropFirst("models/".count))
    } else {
      self.model = rawModel
    }

    // Validate model name
    if self.model.isEmpty {
      throw ToneAnalysisError.invalidModelName(settings.geminiModel)
    }

    self.timeoutSeconds = settings.requestTimeoutSeconds
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

    throw ToneAnalysisError.missingApiKey("Gemini")
  }

  private func makeGenerateContentURL(apiVersion: String, apiKey: String) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw ToneAnalysisError.invalidBaseURL
    }

    var basePath = components.path
    if basePath.hasSuffix("/") {
      basePath.removeLast()
    }
    components.path = basePath + "/\(apiVersion)/models/\(model):generateContent"

    var items = components.queryItems ?? []
    items.removeAll { $0.name == "key" }
    items.append(URLQueryItem(name: "key", value: apiKey))
    components.queryItems = items

    guard let url = components.url else { throw ToneAnalysisError.invalidBaseURL }
    return url
  }

  private func generate(prompt: String, apiKey: String) async throws -> String {
    let versionsToTry = ["v1beta", "v1"]
    var lastError: Error?

    for (index, version) in versionsToTry.enumerated() {
      let url = try makeGenerateContentURL(apiVersion: version, apiKey: apiKey)
      var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
      request.httpMethod = "POST"
      request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")

      let body = GeminiToneRequest(
        contents: [
          .init(role: "user", parts: [.init(text: prompt)]),
        ],
        generationConfig: .init(temperature: 0.0, maxOutputTokens: config.maxOutputTokens)
      )
      request.httpBody = try JSONEncoder().encode(body)

      do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
          lastError = ToneAnalysisError.requestFailed(-1, nil)
          continue
        }

        if (200..<300).contains(http.statusCode) {
          let decoded = try JSONDecoder().decode(GeminiToneResponse.self, from: data)
          let textParts = decoded.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            ?? []

          // Check if response is empty
          let joined = textParts.joined()
          guard !joined.isEmpty else {
            throw ToneAnalysisError.emptyResponse
          }
          return joined
        }

        let message = parseErrorMessage(data: data)
        NSLog("[TextPolish] Gemini Tone HTTP \(http.statusCode) message=\(message ?? "nil")")

        // Handle rate limiting with exponential backoff
        if http.statusCode == 429 {
          let retryAfter = extractRetryAfter(from: data) ?? 2
          try await Task.sleep(for: .seconds(retryAfter))
          // Don't set lastError, just retry this same version
          continue
        }

        if http.statusCode == 404, index < versionsToTry.count - 1 {
          lastError = ToneAnalysisError.requestFailed(http.statusCode, message)
          continue
        }

        throw ToneAnalysisError.requestFailed(http.statusCode, message)
      } catch {
        // If it's already a ToneAnalysisError, rethrow it
        if error is ToneAnalysisError {
          throw error
        }
        // Otherwise, treat as a network error
        lastError = error
        continue
      }
    }

    throw lastError ?? ToneAnalysisError.requestFailed(-1, nil)
  }

  private func extractRetryAfter(from data: Data) -> Double? {
    guard let string = String(data: data, encoding: .utf8) else { return nil }
    guard let range = string.range(of: #"retryAfter"\s*:\s*(\d+)"#, options: .regularExpression) else { return nil }
    let match = string[range]
    let numberString = match.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
    if let number = Int(numberString) {
      return Double(number)
    }
    return nil
  }

  private struct GoogleErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
      let code: Int?
      let message: String?
      let status: String?
    }
    let error: ErrorBody?
  }

  private func parseErrorMessage(data: Data) -> String? {
    if let decoded = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data) {
      let message = decoded.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let message, !message.isEmpty { return message }
      let status = decoded.error?.status?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let status, !status.isEmpty { return status }
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

private struct GeminiToneRequest: Encodable {
  struct Content: Encodable {
    struct Part: Encodable {
      let text: String
    }
    let role: String
    let parts: [Part]
  }

  struct GenerationConfig: Encodable {
    let temperature: Double
    let maxOutputTokens: Int
  }

  let contents: [Content]
  let generationConfig: GenerationConfig
}

private struct GeminiToneResponse: Decodable {
  struct Candidate: Decodable {
    struct Content: Decodable {
      struct Part: Decodable {
        let text: String?
      }
      let parts: [Part]?
    }
    let content: Content?
  }

  let candidates: [Candidate]?
}

extension GeminiToneAnalyzer: @unchecked Sendable {}
