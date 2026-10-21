import Foundation

extension Settings {
  /// Any service that speaks the OpenAI chat completions API, such as Groq, DeepSeek, Mistral, Together,
  /// or a local Ollama or LM Studio. The API key is optional because local servers often need none.
  struct CustomProvider: Codable, Equatable, Sendable {
    /// For example https://api.groq.com/openai/v1 or http://localhost:11434/v1. Empty until the user sets it.
    var baseURL: String
    var model: String
    var apiKey: String?
    var maxAttempts: Int
    var minSimilarity: Double
    var extraInstruction: String?

    init(
      baseURL: String = "",
      model: String = "",
      apiKey: String? = nil,
      maxAttempts: Int = 2,
      minSimilarity: Double = 0.65,
      extraInstruction: String? = nil
    ) {
      self.baseURL = baseURL
      self.model = model
      self.apiKey = apiKey
      self.maxAttempts = maxAttempts
      self.minSimilarity = minSimilarity
      self.extraInstruction = extraInstruction
      normalize()
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
        baseURL: (try? container.decodeIfPresent(String.self, forKey: .baseURL)) ?? "",
        model: (try? container.decodeIfPresent(String.self, forKey: .model)) ?? "",
        apiKey: try? container.decodeIfPresent(String.self, forKey: .apiKey),
        maxAttempts: (try? container.decodeIfPresent(Int.self, forKey: .maxAttempts)) ?? 2,
        minSimilarity: (try? container.decodeIfPresent(Double.self, forKey: .minSimilarity)) ?? 0.65,
        extraInstruction: try? container.decodeIfPresent(String.self, forKey: .extraInstruction)
      )
    }

    /// A base URL and a model are enough; the key is optional.
    var isConfigured: Bool {
      !baseURL.isEmpty && !model.isEmpty
    }

    mutating func normalize() {
      baseURL = Self.validURL(baseURL)
      model = model.trimmingCharacters(in: .whitespacesAndNewlines)
      apiKey = Self.nilIfBlank(apiKey)
      maxAttempts = min(8, max(1, maxAttempts))
      minSimilarity = minSimilarity.isFinite ? min(1, max(0, minSimilarity)) : 0.65
      extraInstruction = Self.nilIfBlank(extraInstruction)
    }

    /// The trimmed URL when it is http or https with a host, else empty, so a typo reads as not set up.
    private static func validURL(_ value: String) -> String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = components.host, !host.isEmpty
      else {
        return ""
      }
      return trimmed
    }

    private static func nilIfBlank(_ value: String?) -> String? {
      let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return trimmed.isEmpty ? nil : trimmed
    }
  }
}
