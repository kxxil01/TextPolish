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
