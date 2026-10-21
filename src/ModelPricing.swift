import Foundation

/// List prices for common models, in US dollars per million tokens, to estimate what Polish costs.
/// Provider bills are the final word: prices change, and caching or batch discounts are not counted.
enum ModelPricing {
  struct Price: Equatable, Sendable {
    let input: Double
    let output: Double
  }

  /// Checked October 2026 on the providers' pricing pages.
  private static let prices: [String: Price] = [
    "gpt-4.1": Price(input: 2.00, output: 8.00),
    "gpt-4.1-mini": Price(input: 0.40, output: 1.60),
    "gpt-4.1-nano": Price(input: 0.10, output: 0.40),
    "gpt-4o-mini": Price(input: 0.15, output: 0.60),
    "gpt-5": Price(input: 1.25, output: 10.00),
    "gpt-5-mini": Price(input: 0.25, output: 2.00),
    "gpt-5-nano": Price(input: 0.05, output: 0.40),
    "gemini-2.5-flash": Price(input: 0.30, output: 2.50),
    "gemini-2.5-flash-lite": Price(input: 0.10, output: 0.40),
    "gemini-2.5-pro": Price(input: 1.25, output: 10.00),
    "claude-haiku-4-5": Price(input: 1.00, output: 5.00),
    "claude-sonnet-4-5": Price(input: 3.00, output: 15.00),
  ]

  /// The price for a model name, matching dated versions ("gpt-4.1-mini-2025-04-14") and OpenRouter names
  /// ("openai/gpt-4.1-mini"). Free OpenRouter models cost nothing. Nil when the model is not known.
  static func price(for model: String) -> Price? {
    let name = model.lowercased()
    if name.hasSuffix(":free") {
      return Price(input: 0, output: 0)
    }
    let bareName = name.split(separator: "/").last.map(String.init) ?? name
    let match = prices.keys
      .filter { bareName == $0 || isVersion(of: $0, bareName) }
      .max { $0.count < $1.count }
    return match.flatMap { prices[$0] }
  }

  /// "gpt-4.1-mini-2025-04-14" or "gemini-2.5-flash-preview" are versions of a known model; "gpt-4.1-mini" is not
  /// a version of "gpt-4.1".
  private static func isVersion(of known: String, _ name: String) -> Bool {
    guard name.hasPrefix(known + "-") else { return false }
    let rest = name.dropFirst(known.count + 1)
    return rest.first?.isNumber == true || rest.hasPrefix("latest") || rest.hasPrefix("preview")
  }

  /// Estimated dollars for these tokens, or nil when the model's price is not known.
  static func cost(model: String, inputTokens: Int, outputTokens: Int) -> Double? {
    guard let price = price(for: model) else { return nil }
    return (Double(inputTokens) * price.input + Double(outputTokens) * price.output) / 1_000_000
  }
}
