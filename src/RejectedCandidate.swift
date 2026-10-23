import Foundation

/// A result a provider produced that failed one of TextPolish's checks. Instead of giving up, Polish shows it in
/// the preview with what was flagged, and the writer decides.
struct RejectedCandidate: Equatable, Sendable {
  let text: String
  let reason: CorrectionRetryReason

  /// Only checks a person can judge from the text qualify. A refusal, an overly long answer, or a dropped
  /// placeholder (code, links, Never Change words) is never offered.
  init?(text: String, reason: CorrectionRetryReason) {
    switch reason {
    case .numbersChanged, .overRewrite, .lineStructureChanged:
      self.text = text
      self.reason = reason
    case .refusal, .outputTooLong, .placeholdersMissing:
      return nil
    }
  }

  /// What the preview says above the result.
  var warning: String {
    switch reason {
    case .numbersChanged(let numbers):
      let list = numbers.map { "\"\($0)\"" }.joined(separator: ", ")
      return "Check this: \(list) is not in the result. Paste only if the change is right."
    case .overRewrite:
      return "Check this: it changes more than this style usually does. Paste only if it still says what you meant."
    case .lineStructureChanged:
      return "Check this: the line breaks changed. Paste only if the layout is right."
    case .refusal, .outputTooLong, .placeholdersMissing:
      return ""
    }
  }
}

/// A corrector that remembers its last rejected result, so a Polish that fails every check can still be reviewed.
protocol RejectionReporting {
  var lastRejected: RejectedCandidate? { get }
}
