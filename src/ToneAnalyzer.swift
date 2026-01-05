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

/// Represents the sentiment of text
enum Sentiment: String, Codable, CaseIterable, Sendable {
  case positive = "Positive"
  case negative = "Negative"
  case neutral = "Neutral"
  case mixed = "Mixed"

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self).lowercased()
    switch raw {
    case "positive": self = .positive
    case "negative": self = .negative
    case "neutral": self = .neutral
    case "mixed": self = .mixed
    default: self = .neutral
    }
  }
}

/// Represents the formality level of text
enum FormalityLevel: String, Codable, CaseIterable, Sendable {
  case formal = "Formal"
  case semiFormal = "Semi-formal"
  case casual = "Casual"

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let raw = try container.decode(String.self).lowercased()
    switch raw {
    case "formal": self = .formal
    case "semi-formal", "semiformal": self = .semiFormal
    case "casual": self = .casual
    default: self = .casual
    }
  }
}

/// The result of tone analysis
struct ToneAnalysisResult: Sendable {
  let tone: DetectedTone
  let sentiment: Sentiment
  let formality: FormalityLevel
  let explanation: String
}

/// Internal JSON structure for API responses
struct ToneAnalysisJSON: Decodable {
  let tone: DetectedTone
  let sentiment: Sentiment
  let formality: FormalityLevel
  let explanation: String
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
      let parsed = try JSONDecoder().decode(ToneAnalysisJSON.self, from: data)
      return ToneAnalysisResult(
        tone: parsed.tone,
        sentiment: parsed.sentiment,
        formality: parsed.formality,
        explanation: parsed.explanation
      )
    } catch {
      throw ToneAnalysisError.invalidResponse(error.localizedDescription)
    }
  }
}
