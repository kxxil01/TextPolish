import Foundation

final class GeminiCorrector: GrammarCorrector {
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

  // MARK: - Cached Regex Patterns

  private static let fencedCodeBlockRegex = try! NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
  private static let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`\\n]*`", options: [])
  private static let discordTokenRegex = try! NSRegularExpression(pattern: "<[^>\\n]+>", options: [])
  private static let urlRegex = try! NSRegularExpression(pattern: "https?://[^\\s]+", options: [])

  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let keychainAccount = "geminiApiKey"
  private let keychainLabel = "TextPolish — Gemini API Key"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let maxAttempts: Int
  private let minSimilarity: Double
  private let extraInstruction: String?
  private let correctionLanguage: Settings.CorrectionLanguage

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
    self.maxAttempts = max(1, settings.geminiMaxAttempts)
    self.minSimilarity = max(0.0, min(1.0, settings.geminiMinSimilarity))
    self.extraInstruction = settings.geminiExtraInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.correctionLanguage = settings.correctionLanguage
  }

  func correct(_ text: String) async throws -> String {
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
    do {
      let keyFromPrimaryKeychain =
        try Keychain.getPassword(service: keychainService, account: keychainAccount)
          .trimmingCharacters(in: .whitespacesAndNewlines)
      if !keyFromPrimaryKeychain.isEmpty { return keyFromPrimaryKeychain }
    } catch {
      NSLog("[TextPolish] Failed to read primary keychain: \(error)")
    }

    do {
      let keyFromLegacyKeychain =
        try Keychain.getPassword(service: legacyKeychainService, account: keychainAccount)
          .trimmingCharacters(in: .whitespacesAndNewlines)
      if !keyFromLegacyKeychain.isEmpty {
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

  private func generate(prompt: String, apiKey: String) async throws -> String {
    let versionsToTry = ["v1beta", "v1"]
    var lastError: Error?

    for (index, version) in versionsToTry.enumerated() {
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

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        lastError = GeminiError.requestFailed(-1, nil)
        continue
      }

      if (200..<300).contains(http.statusCode) {
        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        if let blockReason = decoded.promptFeedback?.blockReason, !blockReason.isEmpty {
          throw GeminiError.blocked(blockReason)
        }

        let textParts = decoded.candidates?
          .first?
          .content?
          .parts?
          .compactMap(\.text)
          ?? []

        return textParts.joined()
      }

      let message = parseErrorMessage(data: data)
      NSLog("[TextPolish] Gemini HTTP \(http.statusCode) url=\(sanitize(url)) message=\(message ?? "nil")")

      if http.statusCode == 404, index < versionsToTry.count - 1 {
        lastError = GeminiError.requestFailed(http.statusCode, message)
        continue
      }

      throw GeminiError.requestFailed(http.statusCode, message)
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
    return similarity(original, candidate) >= minSimilarity
  }

  private func newlineCount(in string: String) -> Int {
    string.unicodeScalars.reduce(into: 0) { count, scalar in
      if scalar.value == 10 { count += 1 } // "\n"
    }
  }

  private func similarity(_ a: String, _ b: String) -> Double {
    let aScalars = Array(a.unicodeScalars)
    let bScalars = Array(b.unicodeScalars)
    let maxLen = max(aScalars.count, bScalars.count)
    guard maxLen > 0 else { return 1.0 }
    let distance = levenshteinDistance(aScalars, bScalars)
    return 1.0 - (Double(distance) / Double(maxLen))
  }

  private func levenshteinDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    let (longer, shorter) = a.count >= b.count ? (a, b) : (b, a)
    let m = shorter.count

    var previous = Array(0...m)
    var current = Array(repeating: 0, count: m + 1)

    for (i, longerScalar) in longer.enumerated() {
      current[0] = i + 1
      for (j, shorterScalar) in shorter.enumerated() {
        let cost = longerScalar == shorterScalar ? 0 : 1
        current[j + 1] = min(
          previous[j + 1] + 1,
          current[j] + 1,
          previous[j] + cost
        )
      }
      swap(&previous, &current)
    }

    return previous[m]
  }

  private func cleanup(_ string: String, original: String) -> String {
    let (origPrefix, origCore, origSuffix) = splitOuterWhitespace(original)
    let originalTrimmed = origCore.trimmingCharacters(in: .whitespacesAndNewlines)

    var cleanedCore = string.trimmingCharacters(in: .whitespacesAndNewlines)

    if cleanedCore.hasPrefix("```"),
       cleanedCore.hasSuffix("```"),
       !(originalTrimmed.hasPrefix("```") && originalTrimmed.hasSuffix("```"))
    {
      var lines = cleanedCore.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      if lines.count >= 2, lines.first?.hasPrefix("```") == true, lines.last == "```" {
        lines.removeFirst()
        lines.removeLast()
        cleanedCore = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    if cleanedCore.count >= 2,
       cleanedCore.first == "\"",
       cleanedCore.last == "\"",
       !(originalTrimmed.first == "\"" && originalTrimmed.last == "\"")
    {
      cleanedCore = String(cleanedCore.dropFirst().dropLast())
    }

    cleanedCore = enforcePunctuationPolicy(cleanedCore, original: origCore)

    if origCore.isEmpty { return cleanedCore }
    return origPrefix + cleanedCore + origSuffix
  }

  private func enforcePunctuationPolicy(_ text: String, original: String) -> String {
    var result = text
    if !original.contains(";") {
      result = result.replacingOccurrences(of: ";", with: ",")
    }
    if !original.contains("--") {
      result = result.replacingOccurrences(of: "--", with: "-")
    }
    if !original.contains("—") {
      result = result.replacingOccurrences(of: "—", with: "-")
    }
    return result
  }

  private func splitOuterWhitespace(_ string: String) -> (prefix: String, core: String, suffix: String) {
    var start = string.startIndex
    while start < string.endIndex, string[start].isWhitespace {
      start = string.index(after: start)
    }

    var end = string.endIndex
    while end > start {
      let before = string.index(before: end)
      if string[before].isWhitespace {
        end = before
      } else {
        break
      }
    }

    let prefix = String(string[..<start])
    let core = String(string[start..<end])
    let suffix = String(string[end...])
    return (prefix, core, suffix)
  }

  private struct ProtectedText {
    let text: String
    let placeholders: [String: String]
  }

  private func protect(_ text: String) -> ProtectedText {
    var counter = 0
    var placeholders: [String: String] = [:]
    var current = text
    let namespace = UUID().uuidString
      .replacingOccurrences(of: "-", with: "")
      .prefix(8)

    let regexes = [
      Self.fencedCodeBlockRegex,
      Self.inlineCodeRegex,
      Self.discordTokenRegex,
      Self.urlRegex,
    ]

    for regex in regexes {
      current = protectMatches(
        in: current,
        regex: regex,
        namespace: String(namespace),
        counter: &counter,
        placeholders: &placeholders
      )
    }

    return ProtectedText(text: current, placeholders: placeholders)
  }

  private func protectMatches(
    in text: String,
    regex: NSRegularExpression,
    namespace: String,
    counter: inout Int,
    placeholders: inout [String: String]
  ) -> String {
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    let matches = regex.matches(in: text, range: range)
    guard !matches.isEmpty else { return text }

    var result = text as NSString
    for match in matches.reversed() {
      let original = nsText.substring(with: match.range)
      let token = "⟦GC_PROTECT_\(namespace)_\(counter)⟧"
      counter += 1
      placeholders[token] = original
      result = result.replacingCharacters(in: match.range, with: token) as NSString
    }
    return result as String
  }

  private func restore(_ text: String, placeholders: [String: String]) -> String {
    var restored = text
    for (token, original) in placeholders {
      restored = restored.replacingOccurrences(of: token, with: original)
    }
    return restored
  }

  private func placeholdersAllPresent(in text: String, placeholders: [String: String]) -> Bool {
    for token in placeholders.keys {
      if !text.contains(token) { return false }
    }
    return true
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
