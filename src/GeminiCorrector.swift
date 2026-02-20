import Foundation

final class GeminiCorrector: GrammarCorrector, TextProcessor, RetryReporting, DiagnosticsProviderReporting {
  enum GeminiError: Error, LocalizedError {
    case missingApiKey
    case invalidBaseURL
    case blocked(String?)
    case requestFailed(Int, String?)
    case emptyResponse
    case overRewrite

    var errorDescription: String? {
      switch self {
      case .missingApiKey:
        return "Missing Gemini API key"
      case .invalidBaseURL:
        return "Invalid Gemini base URL"
      case .blocked(let reason):
        return reason.map { "Gemini blocked: \($0)" } ?? "Gemini blocked"
      case .requestFailed(let status, let message):
        if status == 404 {
          if let message, !message.isEmpty {
            return "Gemini request failed (404): \(message) — try Provider → Detect Gemini Model… (or Set Gemini Model…) "
          }
          return "Gemini request failed (404) — try Provider → Detect Gemini Model… (or Set Gemini Model…)"
        }
        if status == 429 {
          return "Gemini quota exceeded (429) — check billing/rate limits or switch Provider → OpenRouter"
        }
        if let message, !message.isEmpty {
          return "Gemini request failed (\(status)): \(message)"
        }
        return "Gemini request failed (\(status))"
      case .emptyResponse:
        return "Gemini returned no text"
      case .overRewrite:
        return "Gemini rewrote too much (try again or use OpenRouter)"
      }
    }
  }

  // MARK: - TextProcessor Requirements

  let minSimilarity: Double

  static let fencedCodeBlockRegex = try! NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
  static let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`\\n]*`", options: [])
  static let discordTokenRegex = try! NSRegularExpression(pattern: "<[^>\\n]+>", options: [])
  static let urlRegex = try! NSRegularExpression(pattern: "https?://[^\\s]+", options: [])

  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let keychainAccount = "geminiApiKey"
  private let keychainLabel = "TextPolish — Gemini API Key"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let session: URLSession
  private let maxAttempts: Int
  private let retryPolicy: RetryPolicy
  private let extraInstruction: String?
  private let correctionLanguage: Settings.CorrectionLanguage
  private(set) var lastRetryCount: Int = 0

  var diagnosticsProvider: Settings.Provider { .gemini }
  var diagnosticsModel: String { model }

  init(settings: Settings) throws {
    keyFromSettings = settings.geminiApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv =
      ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ??
      ProcessInfo.processInfo.environment["GOOGLE_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.geminiBaseURL) else { throw GeminiError.invalidBaseURL }

    self.baseURL = baseURL
    let rawModel = settings.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
    if rawModel.hasPrefix("models/") {
      self.model = String(rawModel.dropFirst("models/".count))
    } else {
      self.model = rawModel
    }
    self.timeoutSeconds = settings.requestTimeoutSeconds
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = timeoutSeconds
    configuration.timeoutIntervalForResource = timeoutSeconds
    self.session = URLSession(configuration: configuration)
    self.maxAttempts = max(1, settings.geminiMaxAttempts)
    self.retryPolicy = RetryPolicy(maxNetworkAttempts: 3, maxRateLimitBackoffSeconds: 12)
    self.minSimilarity = max(0.0, min(1.0, settings.geminiMinSimilarity))
    self.extraInstruction = settings.geminiExtraInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
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
      guard !cleaned.isEmpty else { throw GeminiError.emptyResponse }

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

    throw GeminiError.overRewrite
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

    throw GeminiError.missingApiKey
  }

  private func makeGenerateContentURL(apiVersion: String, apiKey: String) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw GeminiError.invalidBaseURL
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

    guard let url = components.url else { throw GeminiError.invalidBaseURL }
    return url
  }

  private enum GeminiVersionFallback: Error {
    case tryNextVersion
  }

  private func generate(prompt: String, apiKey: String) async throws -> String {
    let versionsToTry = ["v1beta", "v1"]
    var lastError: Error?
    var retryCount = 0
    defer { lastRetryCount = retryCount }

    for (index, version) in versionsToTry.enumerated() {
      do {
        let response: String = try await retryPolicy.performWithBackoff(
          maxAttempts: retryPolicy.maxNetworkAttempts,
          onRetry: { retryCount += 1 }
        ) { attempt, isLastAttempt in
          let url = try makeGenerateContentURL(apiVersion: version, apiKey: apiKey)
          var request = URLRequest(url: url, timeoutInterval: timeoutSeconds)
          request.httpMethod = "POST"
          request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
          request.setValue("TextPolish/0.1", forHTTPHeaderField: "User-Agent")

          let body = GeminiGenerateContentRequest(
            contents: [
              .init(role: "user", parts: [.init(text: prompt)]),
            ],
            generationConfig: .init(temperature: 0.0, maxOutputTokens: 1024)
          )
          request.httpBody = try JSONEncoder().encode(body)

          do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
              let error = GeminiError.requestFailed(-1, nil)
              lastError = error
              if isLastAttempt {
                return .fail(error)
              }
              return .retry(after: retryPolicy.retryDelaySeconds(attempt: attempt), lastError: error)
            }

            if (200..<300).contains(http.statusCode) {
              let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
              if let blockReason = decoded.promptFeedback?.blockReason, !blockReason.isEmpty {
                return .fail(GeminiError.blocked(blockReason))
              }

              let textParts = decoded.candidates?
                .first?
                .content?
                .parts?
                .compactMap(\.text)
                ?? []

              return .success(textParts.joined())
            }

            let message = ErrorLogSanitizer.sanitize(parseErrorMessage(data: data))
            NSLog("[TextPolish] Gemini HTTP \(http.statusCode) url=\(sanitize(url)) message=\(message ?? "nil")")

            if http.statusCode == 404, index < versionsToTry.count - 1 {
              let error = GeminiError.requestFailed(http.statusCode, message)
              lastError = error
              return .fail(GeminiVersionFallback.tryNextVersion)
            }

            let requestError = GeminiError.requestFailed(http.statusCode, message)

            if http.statusCode == 429, !isLastAttempt {
              lastError = requestError
              let requestedRetryAfter = RetryAfterParser.retryAfterSeconds(from: http, data: data)
                ?? retryPolicy.retryDelaySeconds(attempt: attempt)
              let retryAfter = retryPolicy.clampedRateLimitBackoff(requestedRetryAfter)
              return .retry(after: retryAfter, lastError: requestError)
            }

            if (500...599).contains(http.statusCode), !isLastAttempt {
              lastError = requestError
              return .retry(after: retryPolicy.retryDelaySeconds(attempt: attempt), lastError: requestError)
            }

            return .fail(requestError)
          } catch {
            if error is CancellationError { throw error }
            if let geminiError = error as? GeminiError {
              return .fail(geminiError)
            }

            let sanitizedErrorDescription = ErrorLogSanitizer.sanitize(error.localizedDescription)
            let wrapped = GeminiError.requestFailed(-1, sanitizedErrorDescription)
            lastError = wrapped
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

    throw lastError ?? GeminiError.requestFailed(-1, nil)
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

  private func sanitize(_ url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.absoluteString
    }
    components.queryItems = (components.queryItems ?? []).map { item in
      if item.name == "key" { return URLQueryItem(name: item.name, value: "REDACTED") }
      return item
    }
    return components.url?.absoluteString ?? url.absoluteString
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

private struct GeminiGenerateContentRequest: Encodable {
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

private struct GeminiGenerateContentResponse: Decodable {
  struct Candidate: Decodable {
    struct Content: Decodable {
      struct Part: Decodable {
        let text: String?
      }
      let parts: [Part]?
    }
    let content: Content?
  }

  struct PromptFeedback: Decodable {
    let blockReason: String?
  }

  let candidates: [Candidate]?
  let promptFeedback: PromptFeedback?
}

extension GeminiCorrector: @unchecked Sendable {}
