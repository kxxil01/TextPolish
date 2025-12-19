import Foundation

@MainActor
final class OpenRouterCorrector: GrammarCorrector {
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
          return "OpenRouter payment required (402) — add credits or use a free model (Backend → Set OpenRouter Model… / Detect OpenRouter Model…)"
        }
        if status == 404 {
          if let message, !message.isEmpty {
            return "OpenRouter request failed (404): \(message) — try Backend → Detect OpenRouter Model… (or Set OpenRouter Model…)"
          }
          return "OpenRouter model not found (404) — try Backend → Detect OpenRouter Model… (or Set OpenRouter Model…)"
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
        return "OpenRouter rewrote too much (try again or adjust model)"
      }
    }
  }

  private let baseURL: URL
  private let model: String
  private let keychainService: String
  private let legacyKeychainService = "com.ilham.GrammarCorrection"
  private let keychainAccount = "openRouterApiKey"
  private let keychainLabel = "TextPolish — OpenRouter API Key"
  private let keyFromSettings: String?
  private let keyFromEnv: String?
  private let timeoutSeconds: Double
  private let maxAttempts: Int
  private let minSimilarity: Double
  private let extraInstruction: String?

  init(settings: Settings) throws {
    keyFromSettings = settings.openRouterApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    keyFromEnv = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]
    keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    guard let baseURL = URL(string: settings.openRouterBaseURL) else { throw OpenRouterError.invalidBaseURL }

    self.baseURL = baseURL
    self.model = settings.openRouterModel.trimmingCharacters(in: .whitespacesAndNewlines)
    self.timeoutSeconds = settings.requestTimeoutSeconds
    self.maxAttempts = max(1, settings.openRouterMaxAttempts)
    self.minSimilarity = max(0.0, min(1.0, settings.openRouterMinSimilarity))
    self.extraInstruction = settings.openRouterExtraInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
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
      guard !cleaned.isEmpty else { throw OpenRouterError.emptyResponse }

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

    throw OpenRouterError.overRewrite
  }

  private func resolveApiKey() throws -> String {
    let keyFromPrimaryKeychain =
      (try? Keychain.getPassword(service: keychainService, account: keychainAccount))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromPrimaryKeychain.isEmpty { return keyFromPrimaryKeychain }

    let keyFromLegacyKeychain =
      (try? Keychain.getPassword(service: legacyKeychainService, account: keychainAccount))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !keyFromLegacyKeychain.isEmpty {
      if legacyKeychainService != keychainService {
        try? Keychain.setPassword(keyFromLegacyKeychain, service: keychainService, account: keychainAccount, label: keychainLabel)
      }
      return keyFromLegacyKeychain
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

    var basePath = components.path
    if basePath.hasSuffix("/") { basePath.removeLast() }
    components.path = basePath + "/chat/completions"

    guard let url = components.url else { throw OpenRouterError.invalidBaseURL }
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

    let body = OpenRouterChatCompletionsRequest(
      model: model,
      messages: [
        .init(role: "user", content: prompt),
      ],
      temperature: 0.0,
      maxTokens: 1024
    )
    request.httpBody = try JSONEncoder().encode(body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw OpenRouterError.requestFailed(-1, nil)
    }

    if (200..<300).contains(http.statusCode) {
      let decoded = try JSONDecoder().decode(OpenRouterChatCompletionsResponse.self, from: data)
      let content = decoded.choices?.first?.message?.content ?? ""
      return content
    }

    let message = parseErrorMessage(data: data)
    NSLog("[TextPolish] OpenRouter HTTP \(http.statusCode) model=\(model) message=\(message ?? "nil")")
    throw OpenRouterError.requestFailed(http.statusCode, message)
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

  private func makePrompt(text: String, attempt: Int) -> String {
    var lines: [String] = [
      "You are a grammar and typo corrector.",
      "Make the smallest possible edits to fix spelling, typos, grammar, and obvious punctuation mistakes. Do NOT introduce em dashes (—), double hyphens (--), or semicolons (;) unless they already appear in the original text.",
      "Do NOT rewrite, rephrase, translate, or change tone/voice. Keep the writing natural and human.",
      "Do NOT expand slang/abbreviations, and do NOT make it more formal.",
      "Preserve formatting exactly: whitespace, line breaks, indentation, Markdown, emojis, mentions (@user, #channel), links, and code blocks.",
      "Tokens like ⟦GC_PROTECT_XXXX_0⟧ are protected placeholders and must remain unchanged.",
      "Return ONLY the corrected text. No explanations, no quotes, no code fences.",
      "",
      "TEXT:",
      text,
    ]

    if let extraInstruction, !extraInstruction.isEmpty {
      lines.insert("Extra instruction: \(extraInstruction)", at: 7)
    }

    if attempt > 1 {
      lines.insert(
        "IMPORTANT: Your previous output changed the text too much. This time, keep everything identical except for the minimal characters needed to correct errors.",
        at: 2
      )
    }

    return lines.joined(separator: "\n")
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

    if origCore.isEmpty { return cleanedCore }
    return origPrefix + cleanedCore + origSuffix
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

    let patterns: [String] = [
      "```[\\s\\S]*?```", // fenced code blocks (multiline)
      "`[^`\\n]*`", // inline code
      "<[^>\\n]+>", // Discord tokens like <@id>, <#id>, <:name:id>
      "https?://[^\\s]+", // URLs
    ]

    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
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
