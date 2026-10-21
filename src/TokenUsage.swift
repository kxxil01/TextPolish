import Foundation

/// Tokens one request used, as the provider reported them in the response body.
struct TokenUsage: Equatable, Sendable {
  let input: Int
  let output: Int

  /// Reads OpenAI-format `usage` (OpenAI, OpenRouter, Custom), Anthropic `usage`, or Gemini `usageMetadata`.
  /// Nil when the body has no counts, as some compatible servers leave them out.
  static func parse(_ data: Data) -> TokenUsage? {
    guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
    if let usage = body.usage {
      let input = usage.promptTokens ?? usage.inputTokens
      let output = usage.completionTokens ?? usage.outputTokens
      guard let input, let output else { return nil }
      return TokenUsage(input: input, output: output)
    }
    if let metadata = body.usageMetadata, let input = metadata.promptTokenCount {
      // Gemini bills its thinking tokens as output.
      let output = (metadata.candidatesTokenCount ?? 0) + (metadata.thoughtsTokenCount ?? 0)
      return TokenUsage(input: input, output: output)
    }
    return nil
  }

  private struct Body: Decodable {
    struct Usage: Decodable {
      let promptTokens: Int?
      let completionTokens: Int?
      let inputTokens: Int?
      let outputTokens: Int?

      private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
      }
    }

    struct UsageMetadata: Decodable {
      let promptTokenCount: Int?
      let candidatesTokenCount: Int?
      let thoughtsTokenCount: Int?
    }

    let usage: Usage?
    let usageMetadata: UsageMetadata?
  }
}
