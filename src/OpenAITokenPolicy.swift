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
}

