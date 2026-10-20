/// How far a correction may change the text.
enum CorrectionStyle: Sendable, Equatable {
  /// Fix spelling, grammar, and punctuation with the smallest possible edits.
  case minimal
  /// Also lightly rephrase unclear wording so it reads naturally, keeping meaning and tone.
  case clarify

  /// Clarifying rephrases more, so it accepts lower similarity, but a floor still rejects output that drifts.
  func minimumSimilarity(configured: Double) -> Double {
    switch self {
    case .minimal: return configured
    case .clarify: return min(configured, 0.4)
    }
  }
}

protocol GrammarCorrector: Sendable {
  func correct(_ text: String) async throws -> String
  func correct(_ text: String, style: CorrectionStyle) async throws -> String
}

extension GrammarCorrector {
  /// Correctors without style support treat every request as a minimal correction.
  func correct(_ text: String, style: CorrectionStyle) async throws -> String {
    try await correct(text)
  }
}
