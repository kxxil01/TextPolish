import Foundation

/// Protocol for text processing functionality shared between corrector implementations
protocol TextProcessor {
  /// The minimum similarity threshold for accepting corrections
  var minSimilarity: Double { get }

  /// Regex patterns for text protection
  static var fencedCodeBlockRegex: NSRegularExpression { get }
  static var inlineCodeRegex: NSRegularExpression { get }
  static var discordTokenRegex: NSRegularExpression { get }
  static var urlRegex: NSRegularExpression { get }
}

/// Represents text with protected placeholders
struct ProtectedText {
  let text: String
  let placeholders: [String: String]
}

// MARK: - Default Implementation

private enum TextProcessorRegexDefaults {
  static let fencedCodeBlockRegex = try! NSRegularExpression(pattern: "```[\\s\\S]*?```", options: [])
  static let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`\\n]*`", options: [])
  static let discordTokenRegex = try! NSRegularExpression(pattern: "<[^>\\n]+>", options: [])
  static let urlRegex = try! NSRegularExpression(pattern: "https?://[^\\s]+", options: [])
}

extension TextProcessor {

  static var fencedCodeBlockRegex: NSRegularExpression {
    TextProcessorRegexDefaults.fencedCodeBlockRegex
  }

  static var inlineCodeRegex: NSRegularExpression {
    TextProcessorRegexDefaults.inlineCodeRegex
  }

  static var discordTokenRegex: NSRegularExpression {
    TextProcessorRegexDefaults.discordTokenRegex
  }

  static var urlRegex: NSRegularExpression {
    TextProcessorRegexDefaults.urlRegex
  }

  /// Protects special text patterns (code blocks, URLs, etc.) by replacing them with placeholders
  func protect(_ text: String) -> ProtectedText {
    var counter = 0
    var placeholders: [String: String] = [:]
    var current = text
    let namespace = UUID().uuidString
      .replacingOccurrences(of: "-", with: "")
      .prefix(8)

    let regexes = [
      Self.fencedCodeBlockRegex,
      Self.inlineCodeRegex,
      Self.discordTokenRegex,
      Self.urlRegex,
    ]

    for regex in regexes {
      current = protectMatches(
        in: current,
        regex: regex,
        namespace: String(namespace),
        counter: &counter,
        placeholders: &placeholders
      )
    }

    return ProtectedText(text: current, placeholders: placeholders)
  }

  /// Protects matches found by a regex pattern
  func protectMatches(
    in text: String,
    regex: NSRegularExpression,
    namespace: String,
    counter: inout Int,
    placeholders: inout [String: String]
  ) -> String {
    let nsText = text as NSString
    let range = NSRange(location: 0, length: nsText.length)
    let matches = regex.matches(in: text, range: range)
    guard !matches.isEmpty else { return text }

    var result = text as NSString
    for match in matches.reversed() {
      let original = nsText.substring(with: match.range)
      let token = "⟦GC_PROTECT_\(namespace)_\(counter)⟧"
      counter += 1
      placeholders[token] = original
      result = result.replacingCharacters(in: match.range, with: token) as NSString
    }
    return result as String
  }

  /// Restores protected placeholders with their original text
  func restore(_ text: String, placeholders: [String: String]) -> String {
    var restored = text
    for (token, original) in placeholders {
      restored = restored.replacingOccurrences(of: token, with: original)
    }
    return restored
  }

  /// Verifies that all placeholders are present in the text
  func placeholdersAllPresent(in text: String, placeholders: [String: String]) -> Bool {
    for token in placeholders.keys {
      if !text.contains(token) { return false }
    }
    return true
  }

  /// Splits string into prefix, core, and suffix based on whitespace
  func splitOuterWhitespace(_ string: String) -> (prefix: String, core: String, suffix: String) {
    var start = string.startIndex
    while start < string.endIndex, string[start].isWhitespace {
      start = string.index(after: start)
    }

    var end = string.endIndex
    while end > start {
      let before = string.index(before: end)
      if string[before].isWhitespace {
        end = before
      } else {
        break
      }
    }

    let prefix = String(string[..<start])
    let core = String(string[start..<end])
    let suffix = String(string[end...])
    return (prefix, core, suffix)
  }

  /// Enforces punctuation policy based on original text
  func enforcePunctuationPolicy(_ text: String, original: String) -> String {
    var result = text
    if !original.contains(";") {
      result = result.replacingOccurrences(of: ";", with: ",")
    }
    if !original.contains("--") {
      result = result.replacingOccurrences(of: "--", with: "-")
    }
    if !original.contains("—") {
      result = result.replacingOccurrences(of: "—", with: "-")
    }
    return result
  }

  /// Cleans up AI-generated text to match original formatting
  func cleanup(_ string: String, original: String) -> String {
    let (origPrefix, origCore, origSuffix) = splitOuterWhitespace(original)
    let originalTrimmed = origCore.trimmingCharacters(in: .whitespacesAndNewlines)

    var cleanedCore = string.trimmingCharacters(in: .whitespacesAndNewlines)

    if cleanedCore.hasPrefix("```"),
       cleanedCore.hasSuffix("```"),
       !(originalTrimmed.hasPrefix("```") && originalTrimmed.hasSuffix("```"))
    {
      var lines = cleanedCore.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      if lines.count >= 2, lines.first?.hasPrefix("```") == true, lines.last == "```" {
        lines.removeFirst()
        lines.removeLast()
        cleanedCore = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    if cleanedCore.count >= 2,
       cleanedCore.first == "\"",
       cleanedCore.last == "\"",
       !(originalTrimmed.first == "\"" && originalTrimmed.last == "\"")
    {
      cleanedCore = String(cleanedCore.dropFirst().dropLast())
    }

    cleanedCore = enforcePunctuationPolicy(cleanedCore, original: origCore)

    if origCore.isEmpty { return cleanedCore }
    return origPrefix + cleanedCore + origSuffix
  }

  /// Counts newlines in a string
  func newlineCount(in string: String) -> Int {
    string.unicodeScalars.reduce(into: 0) { count, scalar in
      if scalar.value == 10 { count += 1 } // "\n"
    }
  }

  /// Calculates similarity between two strings using Levenshtein distance
  func similarity(_ a: String, _ b: String) -> Double {
    let aScalars = Array(a.unicodeScalars)
    let bScalars = Array(b.unicodeScalars)
    let maxLen = max(aScalars.count, bScalars.count)
    guard maxLen > 0 else { return 1.0 }
    let distance = levenshteinDistance(aScalars, bScalars)
    return 1.0 - (Double(distance) / Double(maxLen))
  }

  /// Checks similarity against a minimum threshold with early exits for large inputs
  func isSimilarEnough(original: String, candidate: String, minimum: Double) -> Bool {
    let originalScalars = Array(original.unicodeScalars)
    let candidateScalars = Array(candidate.unicodeScalars)
    let maxLen = max(originalScalars.count, candidateScalars.count)
    guard maxLen > 0 else { return true }

    let clampedMinimum = max(0.0, min(1.0, minimum))
    let allowedDistance = Int(Double(maxLen) * (1.0 - clampedMinimum))
    if allowedDistance <= 0 { return original == candidate }

    let lengthDiff = abs(originalScalars.count - candidateScalars.count)
    if lengthDiff > allowedDistance { return false }

    let distance = boundedLevenshteinDistance(
      originalScalars,
      candidateScalars,
      maxDistance: allowedDistance
    )
    return distance <= allowedDistance
  }

  /// Calculates Levenshtein distance with early exit when exceeding maxDistance
  func boundedLevenshteinDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar], maxDistance: Int) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    let (longer, shorter) = a.count >= b.count ? (a, b) : (b, a)
    let m = shorter.count

    var previous = Array(0...m)
    var current = Array(repeating: 0, count: m + 1)

    for (i, longerScalar) in longer.enumerated() {
      current[0] = i + 1
      var rowMin = current[0]
      for (j, shorterScalar) in shorter.enumerated() {
        let cost = longerScalar == shorterScalar ? 0 : 1
        current[j + 1] = min(
          previous[j + 1] + 1,
          current[j] + 1,
          previous[j] + cost
        )
        if current[j + 1] < rowMin {
          rowMin = current[j + 1]
        }
      }
      if rowMin > maxDistance { return maxDistance + 1 }
      swap(&previous, &current)
    }

    return previous[m]
  }

  /// Calculates Levenshtein distance between two string scalar arrays
  func levenshteinDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    let (longer, shorter) = a.count >= b.count ? (a, b) : (b, a)
    let m = shorter.count

    var previous = Array(0...m)
    var current = Array(repeating: 0, count: m + 1)

    for (i, longerScalar) in longer.enumerated() {
      current[0] = i + 1
      for (j, shorterScalar) in shorter.enumerated() {
        let cost = longerScalar == shorterScalar ? 0 : 1
        current[j + 1] = min(
          previous[j + 1] + 1,
          current[j] + 1,
          previous[j] + cost
        )
      }
      swap(&previous, &current)
    }

    return previous[m]
  }
}
