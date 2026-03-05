import Foundation

/// Represents the detected tone of text
enum DetectedTone: String, Codable, CaseIterable, Sendable {
  case friendly = "Friendly"
  case frustrated = "Frustrated"
  case formal = "Formal"
  case casual = "Casual"
  case direct = "Direct"
  case neutral = "Neutral"
  case sarcastic = "Sarcastic"
  case enthusiastic = "Enthusiastic"
  case concerned = "Concerned"
  case professional = "Professional"

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self).lowercased()
    switch raw {
    case "friendly": self = .friendly
    case "frustrated": self = .frustrated
    case "formal": self = .formal
    case "casual": self = .casual
    case "direct": self = .direct
    case "neutral": self = .neutral
    case "sarcastic": self = .sarcastic
    case "enthusiastic": self = .enthusiastic
    case "concerned": self = .concerned
    case "professional": self = .professional
    default: self = .neutral
    }
  }
}

enum MisunderstandingRiskLevel: String, Codable, CaseIterable, Sendable {
  case low
  case medium
  case high

  var displayName: String {
    switch self {
    case .low: return "Low"
    case .medium: return "Medium"
    case .high: return "High"
    }
  }
}

struct MisunderstandingRisk: Sendable {
  let level: MisunderstandingRiskLevel
  let reason: String
}

/// The result of tone analysis
struct ToneAnalysisResult: Sendable {
  let tone: DetectedTone
  let plainMeaning: String
  let likelyIntent: String
  let misunderstandingRisk: MisunderstandingRisk
  let ambiguities: [String]
  let suggestedReplies: [String]
}

/// Errors specific to tone analysis
enum ToneAnalysisError: Error, LocalizedError {
  case missingApiKey(String)
  case invalidBaseURL
  case requestFailed(Int, String?)
  case emptyResponse
  case invalidResponse(String)
  case textTooShort
  case textTooLong
  case invalidModelName(String)
  case rateLimited

  var errorDescription: String? {
    switch self {
    case .missingApiKey(let provider):
      return "Missing \(provider) API key"
    case .invalidBaseURL:
      return "Invalid base URL"
    case .requestFailed(let status, let message):
      if status == 429 {
        return "Rate limited (429) — try again later"
      }
      if let message, !message.isEmpty {
        return "Request failed (\(status)): \(message)"
      }
      return "Request failed (\(status))"
    case .emptyResponse:
      return "No response received"
    case .invalidResponse(let details):
      return "Could not parse response: \(details)"
    case .textTooShort:
      return "Text is too short to analyze"
    case .textTooLong:
      return "Text is too long to analyze"
    case .invalidModelName(let model):
      return "Invalid model name: \(model)"
    case .rateLimited:
      return "Rate limited - please try again later"
    }
  }
}

/// Configuration for tone analysis
struct ToneAnalysisConfig: Sendable {
  let minTextLength: Int
  let maxTextLength: Int
  let maxOutputTokens: Int

  static let `default` = ToneAnalysisConfig(
    minTextLength: 2,
    maxTextLength: 10000,
    maxOutputTokens: 512
  )
}

/// Protocol for tone analysis providers
protocol ToneAnalyzer: Sendable {
  func analyze(_ text: String) async throws -> ToneAnalysisResult
}

enum ToneAnalysisPromptBuilder {
  static func makePrompt(text: String) -> String {
    let toneOptions = DetectedTone.allCases.map(\.rawValue).joined(separator: ", ")
    return """
    Analyze the message meaning and intent. Return a JSON object with exactly these fields:
    - "tone": one of [\(toneOptions)]
    - "plain_meaning": 1-2 clear sentences that paraphrase what the message means in plain language
    - "likely_intent": a short phrase describing what the sender likely wants
    - "misunderstanding_risk": object with:
      - "level": one of ["low", "medium", "high"]
      - "reason": one short reason for that risk level
    - "ambiguities": array of 0-3 short strings describing ambiguous phrases (empty array if none)
    - "suggested_reply": array of 0-2 concise, safe reply options (empty array if not needed)

    Rules:
    - Keep the output in the same language as the input message.
    - Be concise and literal; do not add facts not implied by the message.
    - Respond with ONLY the JSON object (no markdown, no code fences, no extra text).

    TEXT:
    \(text)
    """
  }
}

/// Common JSON parsing utilities
enum ToneAnalysisJSONParser {
  static func parseResponse(_ response: String) throws -> ToneAnalysisResult {
    var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove markdown code fences if present
    if cleaned.hasPrefix("```json") {
      cleaned = String(cleaned.dropFirst(7))
    } else if cleaned.hasPrefix("```") {
      cleaned = String(cleaned.dropFirst(3))
    }
    if cleaned.hasSuffix("```") {
      cleaned = String(cleaned.dropLast(3))
    }
    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !cleaned.isEmpty else { throw ToneAnalysisError.emptyResponse }

    guard let data = cleaned.data(using: .utf8) else {
      throw ToneAnalysisError.invalidResponse("Could not convert to data")
    }

    do {
      let object = try JSONSerialization.jsonObject(with: data, options: [])
      guard let dictionary = object as? [String: Any] else {
        throw ToneAnalysisError.invalidResponse("Top-level response must be a JSON object")
      }

      let tone = try parseTone(from: dictionary)
      let plainMeaning = try requiredString(key: "plain_meaning", in: dictionary)
      let likelyIntent = try requiredString(key: "likely_intent", in: dictionary)
      let misunderstandingRisk = try requiredRisk(key: "misunderstanding_risk", in: dictionary)
      let ambiguities = try requiredStringArray(
        key: "ambiguities",
        in: dictionary,
        limit: 3
      )
      let suggestedReplies = try requiredStringArray(
        key: "suggested_reply",
        in: dictionary,
        limit: 2
      )

      return ToneAnalysisResult(
        tone: tone,
        plainMeaning: plainMeaning,
        likelyIntent: likelyIntent,
        misunderstandingRisk: misunderstandingRisk,
        ambiguities: ambiguities,
        suggestedReplies: suggestedReplies
      )
    } catch let error as ToneAnalysisError {
      throw error
    } catch {
      throw ToneAnalysisError.invalidResponse(error.localizedDescription)
    }
  }

  private static func parseTone(from dictionary: [String: Any]) throws -> DetectedTone {
    let rawTone = try requiredString(key: "tone", in: dictionary)
    switch rawTone.lowercased() {
    case "friendly": return .friendly
    case "frustrated": return .frustrated
    case "formal": return .formal
    case "casual": return .casual
    case "direct": return .direct
    case "neutral": return .neutral
    case "sarcastic": return .sarcastic
    case "enthusiastic": return .enthusiastic
    case "concerned": return .concerned
    case "professional": return .professional
    default:
      throw ToneAnalysisError.invalidResponse("Invalid tone value: \(rawTone)")
    }
  }

  private static func requiredRisk(
    key: String,
    in dictionary: [String: Any]
  ) throws -> MisunderstandingRisk {
    guard let nested = dictionary[key] as? [String: Any] else {
      throw ToneAnalysisError.invalidResponse("Missing required object field: \(key)")
    }

    let levelString = try requiredString(key: "level", in: nested)
    let reason = try requiredString(key: "reason", in: nested)

    let level: MisunderstandingRiskLevel
    switch levelString.lowercased() {
    case "low":
      level = .low
    case "medium":
      level = .medium
    case "high":
      level = .high
    default:
      throw ToneAnalysisError.invalidResponse("Invalid misunderstanding_risk.level: \(levelString)")
    }

    return MisunderstandingRisk(level: level, reason: reason)
  }

  private static func requiredString(key: String, in dictionary: [String: Any]) throws -> String {
    guard let value = dictionary[key] as? String else {
      throw ToneAnalysisError.invalidResponse("Missing required string field: \(key)")
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw ToneAnalysisError.invalidResponse("Empty required string field: \(key)")
    }
    return trimmed
  }

  private static func requiredStringArray(
    key: String,
    in dictionary: [String: Any],
    limit: Int
  ) throws -> [String] {
    guard let rawValues = dictionary[key] as? [Any] else {
      throw ToneAnalysisError.invalidResponse("Missing required array field: \(key)")
    }

    var result: [String] = []
    for rawValue in rawValues {
      guard let stringValue = rawValue as? String else {
        throw ToneAnalysisError.invalidResponse("Array \(key) must contain only strings")
      }
      let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        continue
      }
      result.append(trimmed)
      if result.count >= limit {
        break
      }
    }
    return result
  }
}
