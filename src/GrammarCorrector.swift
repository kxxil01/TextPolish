/// How far a correction may change the text.
enum CorrectionStyle: Sendable, Equatable {
  /// Fix spelling, grammar, and punctuation with the smallest possible edits.
  case minimal
  /// Also lightly rephrase unclear wording so it reads naturally, keeping meaning and tone.
  case clarify
  /// Cut filler and repetition so the text gets to the point, keeping every fact and request.
  case shorten
  /// Polite, professional wording for work email or a client.
  case formal
  /// Warm, casual wording, as a friendly coworker writes in chat.
  case friendly

  /// Every style except Minimal rewrites wording, so they share the rewrite layout rules and checks.
  var rewritesWording: Bool {
    self != .minimal
  }

  /// Rewrites change more characters, so they accept lower similarity, but a floor still rejects output that drifts.
  func minimumSimilarity(configured: Double) -> Double {
    switch self {
    case .minimal: return configured
    case .clarify: return min(configured, 0.4)
    // Shortening and changing tone replace more words while keeping the meaning.
    case .shorten, .formal, .friendly: return min(configured, 0.3)
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
