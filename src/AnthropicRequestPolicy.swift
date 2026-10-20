import Foundation

enum AnthropicRequestPolicy {
  /// Models that still accept sampling parameters. Opus 4.7+, Sonnet 5.x, and Haiku 5.5 reject `temperature` with a 400.
  private static let temperatureModelPrefixes = [
    "claude-3",
    "claude-haiku-4",
    "claude-sonnet-4",
    "claude-opus-4-0",
    "claude-opus-4-1",
    "claude-opus-4-2",
    "claude-opus-4-5",
    "claude-opus-4-6",
  ]

  /// Models that think by default. Low effort keeps short edits fast.
  private static let lowEffortModelPrefixes = [
    "claude-haiku-5",
    "claude-sonnet-5",
    "claude-opus-5",
    "claude-fable-5",
    "claude-mythos-5",
  ]

  static func temperature(model: String) -> Double? {
    let normalized = normalize(model)
    return temperatureModelPrefixes.contains { normalized.hasPrefix($0) } ? 0.0 : nil
  }

  static func effort(model: String) -> String? {
    let normalized = normalize(model)
    return lowEffortModelPrefixes.contains { normalized.hasPrefix($0) } ? "low" : nil
  }

  private static func normalize(_ model: String) -> String {
    model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

/// `output_config` body for Anthropic Messages requests.
struct AnthropicOutputConfig: Encodable, Equatable {
  let effort: String
}
