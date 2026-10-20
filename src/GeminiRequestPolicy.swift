import Foundation

/// `generationConfig` body shared by Gemini correction and tone requests.
struct GeminiGenerationConfig: Encodable, Equatable {
  struct ThinkingConfig: Encodable, Equatable {
    let thinkingBudget: Int?
    let thinkingLevel: String?
  }

  let temperature: Double?
  let maxOutputTokens: Int
  let thinkingConfig: ThinkingConfig?
  let responseMimeType: String?
}

enum GeminiRequestPolicy {
  static func generationConfig(
    model: String,
    maxOutputTokens: Int,
    responseMimeType: String? = nil
  ) -> GeminiGenerationConfig {
    GeminiGenerationConfig(
      temperature: temperature(model: model),
      maxOutputTokens: maxOutputTokens,
      thinkingConfig: thinkingConfig(model: model),
      responseMimeType: responseMimeType
    )
  }

  /// Gemini 3 is tuned for its default temperature; Google warns lower values can cause looping.
  static func temperature(model: String) -> Double? {
    isGemini3(normalize(model)) ? nil : 0.0
  }

  /// Keeps thinking as low as each model allows. Gemini 2.5 Pro cannot disable thinking; 128 is its minimum budget.
  static func thinkingConfig(model: String) -> GeminiGenerationConfig.ThinkingConfig? {
    let normalized = normalize(model)
    if normalized.hasPrefix("gemini-2.5-flash") {
      return .init(thinkingBudget: 0, thinkingLevel: nil)
    }
    if normalized.hasPrefix("gemini-2.5-pro") {
      return .init(thinkingBudget: 128, thinkingLevel: nil)
    }
    if isGemini3(normalized) {
      let level = normalized.contains("pro") ? "low" : "minimal"
      return .init(thinkingBudget: nil, thinkingLevel: level)
    }
    return nil
  }

  private static func isGemini3(_ normalized: String) -> Bool {
    normalized.hasPrefix("gemini-3")
  }

  private static func normalize(_ model: String) -> String {
    var normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.hasPrefix("models/") {
      normalized.removeFirst("models/".count)
    }
    return normalized
  }
}
