import Foundation

enum PromptGuardrails {

  enum GuardrailError: Error, LocalizedError, Equatable {
    case textEmpty
    case textTooLong

    var errorDescription: String? {
      switch self {
      case .textEmpty: return "Text is empty"
      case .textTooLong: return "Text exceeds maximum length"
      }
    }
  }

  static let maxExtraInstructionLength = 500
  static let maxCorrectionInputLength = 10_000
  static let maxOutputLengthRatio = 3.0

  // MARK: - Input Guards

  static func sanitizeExtraInstruction(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }

    // Strip control characters: allow only scalars >= 0x20 or newline (0x0A)
    let stripped = raw.unicodeScalars
      .filter { $0.value >= 0x20 || $0.value == 0x0A }
      .map { Character($0) }

    var result = String(stripped)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if result.count > maxExtraInstructionLength {
      result = String(result.prefix(maxExtraInstructionLength))
    }

    return result.isEmpty ? nil : result
  }

  static func validateInputLength(_ text: String, maxLength: Int) throws {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw GuardrailError.textEmpty }
    guard trimmed.count <= maxLength else { throw GuardrailError.textTooLong }
  }

  /// Escapes closing delimiter tags in user text to prevent delimiter collision.
  /// Replaces `</user_text>` with `<\/user_text>` so the model can't be tricked
  /// by user content that contains the closing tag.
  static func escapeDelimiters(_ text: String) -> String {
    text.replacingOccurrences(of: "</user_text>", with: "<\\/user_text>")
  }

  // MARK: - Output Guards

  static func detectRefusal(_ output: String) -> Bool {
    let lower = output.lowercased()

    let refusalPhrases = [
      "i can't assist",
      "i cannot assist",
      "i can't process",
      "i cannot process",
      "i can't modify",
      "i cannot modify",
      "i'm unable to",
      "i am unable to",
      "as an ai language model",
      "as an ai assistant",
      "as a large language model",
      "i can't help with",
      "i cannot help with",
      "i apologize, but i'm unable",
      "i apologize, but i cannot",
      "i'm sorry, but i can't assist",
      "i'm sorry, but i cannot assist",
      "i'm not able to assist",
      "i am not able to assist",
      "against my programming",
      "against my guidelines",
      "my guidelines prevent me",
      "i must decline",
      "i need to decline",
    ]

    return refusalPhrases.contains { lower.contains($0) }
  }

  static func validateOutputLength(input: String, output: String) -> Bool {
    let inputLen = input.trimmingCharacters(in: .whitespacesAndNewlines).count
    let outputLen = output.trimmingCharacters(in: .whitespacesAndNewlines).count

    guard inputLen > 0 else { return true }
    let ratio = Double(outputLen) / Double(inputLen)
    return ratio <= maxOutputLengthRatio
  }
}
