import NaturalLanguage

/// Recognizes Indonesian text on the Mac itself, so Polish can translate it without a separate shortcut.
enum LanguageDetector {
  /// Shorter texts, such as "ok bro thanks", are too short to tell apart.
  static let minimumWords = 3
  static let threshold = 0.7

  /// Whether most of the text is Indonesian. Malay counts too, since short chat in either reads the same.
  static func isMostlyIndonesian(_ text: String) -> Bool {
    let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
    guard words.count >= minimumWords else { return false }
    let recognizer = NLLanguageRecognizer()
    recognizer.languageConstraints = [.english, .indonesian, .malay]
    recognizer.processString(text)
    let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
    return (hypotheses[.indonesian] ?? 0) + (hypotheses[.malay] ?? 0) >= threshold
  }
}
