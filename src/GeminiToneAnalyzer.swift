import Foundation

final class GeminiToneAnalyzer: ToneAnalyzer, RetryReporting, DiagnosticsProviderReporting {
  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let keychainAccount = "geminiApiKey"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let ownsSession: Bool
  private let retryPolicy: RetryPolicy
  private let config: ToneAnalysisConfig
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .gemini }
  var diagnosticsModel: String { model }

  init(settings: Settings, config: ToneAnalysisConfig = .default, session: URLSession? = nil) throws {
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
    do {
      if let key = try Keychain.getConfiguredPassword(
        primaryService: keychainService,
        account: keychainAccount
      ), !key.isEmpty {
        return key
      }
    } catch {
      TPLogger.log("Failed to read Gemini keychain: \(error)")
    }

    if let keyFromSettings, !keyFromSettings.isEmpty { return keyFromSettings }
    let env = keyFromEnv?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !env.isEmpty { return env }

    throw ToneAnalysisError.missingApiKey("Gemini")
  }

  private func makeGenerateContentURL(apiVersion: String, apiKey: String) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw ToneAnalysisError.invalidBaseURL
    }
    components.path = GeminiEndpointPath.generateContentPath(
      basePath: components.path,
      apiVersion: apiVersion,
      model: model
    )

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
    var retryCount = 0
    defer { lastRetryCount = retryCount }

    enum GeminiVersionFallback: Error {
      case tryNextVersion
    }

    for (index, version) in versionsToTry.enumerated() {
      do {
        let response: String = try await retryPolicy.performWithBackoff(
          maxAttempts: retryPolicy.maxNetworkAttempts,
          onRetry: { retryCount += 1 }
        ) { attempt, isLastAttempt in
          try Task.checkCancellation()

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
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
              let error = ToneAnalysisError.requestFailed(-1, nil)
              if isLastAttempt {
                return .fail(error)
              }
              return .retry(after: retryPolicy.retryDelaySeconds(attempt: attempt), lastError: error)
            }

            if (200..<300).contains(http.statusCode) {
              let decoded = try JSONDecoder().decode(GeminiToneResponse.self, from: data)
              let textParts = decoded.candidates?
                .first?
                .content?
                .parts?
                .compactMap(\.text)
                ?? []
              let joined = textParts.joined()
              guard !joined.isEmpty else {
                return .fail(ToneAnalysisError.emptyResponse)
              }
              return .success(joined)
            }

            let message = ErrorLogSanitizer.sanitize(parseErrorMessage(data: data))
            TPLogger.log("Gemini Tone HTTP \(http.statusCode) message=\(message ?? "nil")")
            let requestError = ToneAnalysisError.requestFailed(http.statusCode, message)

            if http.statusCode == 404, index < versionsToTry.count - 1 {
              lastError = requestError
              return .fail(GeminiVersionFallback.tryNextVersion)
            }

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
            if let urlError = error as? URLError, urlError.code == .cancelled {
              throw CancellationError()
            }
            if let toneError = error as? ToneAnalysisError {
              return .fail(toneError)
            }

            let wrapped = ToneAnalysisError.requestFailed(-1, ErrorLogSanitizer.sanitize(error.localizedDescription))
            if isLastAttempt {
              return .fail(wrapped)
            }
            return .retry(after: retryPolicy.retryDelaySeconds(attempt: attempt), lastError: wrapped)
          }
        }

        return response
      } catch GeminiVersionFallback.tryNextVersion {
        continue
      } catch {
        if error is CancellationError { throw error }
        lastError = error
      }
    }

    throw lastError ?? ToneAnalysisError.requestFailed(-1, nil)
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
      let message = ErrorLogSanitizer.sanitize(decoded.error?.message)
      if let message, !message.isEmpty { return message }
      let status = ErrorLogSanitizer.sanitize(decoded.error?.status)
      if let status, !status.isEmpty { return status }
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
