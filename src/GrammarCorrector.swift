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
  /// The writer's own style, described in their words, such as "short bullet points for a status update".
  case custom(String)
  /// Natural English from text in another language, or a mix, as the same person would write it.
  case translateToEnglish
  /// The writer's draft, in any language, as an English reply to the message they are answering, when known.
  case reply(answering: String?)

  /// Every style except Minimal rewrites wording, so they share the rewrite layout rules and checks.
  var rewritesWording: Bool {
    self != .minimal
  }

  /// Translate and Reply write English from text that may be in another language, so every word can change.
  var translatesToEnglish: Bool {
    switch self {
    case .translateToEnglish, .reply: return true
    default: return false
    }
  }

  /// Rewrites change more characters, so they accept lower similarity, but a floor still rejects output that drifts.
  func minimumSimilarity(configured: Double) -> Double {
    switch self {
    case .minimal: return configured
    case .clarify: return min(configured, 0.4)
    // Shortening and changing tone replace more words while keeping the meaning.
    case .shorten, .formal, .friendly, .custom: return min(configured, 0.3)
    // A translation shares few characters with the original, so only the meaning checks apply.
    case .translateToEnglish, .reply: return 0
    }
  }
}

extension CorrectionStyle: CustomStringConvertible {
  /// The style's name for logs; a custom style's instruction stays out of them.
  var description: String {
    switch self {
    case .minimal: return "minimal"
    case .clarify: return "clarify"
    case .shorten: return "shorten"
    case .formal: return "formal"
    case .friendly: return "friendly"
    case .custom: return "custom"
    case .translateToEnglish: return "translate"
    case .reply(let message): return message == nil ? "reply" : "reply(context)"
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
