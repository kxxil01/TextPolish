import Foundation

enum OpenAITokenPolicy {
  static func usesMaxCompletionTokens(model: String) -> Bool {
    let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }

    if normalized.hasPrefix("o1") || normalized.hasPrefix("o3") || normalized.hasPrefix("o4") {
      return true
    }
    if normalized.hasPrefix("gpt-5") || normalized.hasPrefix("gpt-4.1") {
      return true
    }

    return false
  }

  static func omitsTemperature(model: String) -> Bool {
    let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return false }

    return normalized.hasPrefix("gpt-5")
      || normalized.hasPrefix("o1")
      || normalized.hasPrefix("o3")
      || normalized.hasPrefix("o4")
  }

  /// Reasoning effort for the GPT-5 models documented to accept "minimal" and "low". Corrections use
  /// "minimal" for speed; rewrites use "low" so the model can rephrase well. Other reasoning
  /// models keep their default because accepted values differ per model.
  static func reasoningEffort(model: String, style: CorrectionStyle = .minimal) -> String? {
    let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let minimalEffortModels = ["gpt-5", "gpt-5-mini", "gpt-5-nano"]
    for name in minimalEffortModels where normalized == name || normalized.hasPrefix(name + "-20") {
      return style.rewritesWording ? "low" : "minimal"
    }
    return nil
  }

  /// Models known to accept `response_format: json_object`. Others rely on the prompt asking for JSON.
  static func supportsJSONMode(model: String) -> Bool {
    let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let jsonModePrefixes = ["gpt-4o", "gpt-4.1", "gpt-4-turbo", "gpt-5", "o3", "o4"]
    return jsonModePrefixes.contains { normalized.hasPrefix($0) }
  }

  /// Model kinds that the Chat Completions endpoint rejects or that are not text chat models.
  private static let nonChatMarkers = [
    "realtime", "audio", "tts", "transcribe", "whisper", "image", "dall-e", "embedding",
    "moderation", "search", "instruct", "codex", "computer-use", "deep-research",
  ]

  static func isModelFamily(_ model: String) -> Bool {
    let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.hasPrefix("gpt-") || normalized.hasPrefix("o1") || normalized.hasPrefix("o3") || normalized.hasPrefix("o4")
  }

  /// True for OpenAI models that work with Chat Completions. Pro models are Responses API only.
  static func isChatModel(_ model: String) -> Bool {
    let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard isModelFamily(normalized) else { return false }
    if normalized.hasSuffix("-pro") || normalized.contains("-pro-") {
      return false
    }
    return !nonChatMarkers.contains { normalized.contains($0) }
  }

  static func isTokenParameterError(message: String?) -> Bool {
    let lowered = message?.lowercased() ?? ""
    guard !lowered.isEmpty else { return false }
    if lowered.contains("max_tokens") || lowered.contains("max completion tokens") || lowered.contains("max_completion_tokens") {
      return true
    }
    if lowered.contains("unknown parameter") || lowered.contains("unsupported parameter") {
      return true
    }
    return false
  }
}
