import XCTest

@testable import GrammarCorrection

final class ProviderWordingTests: XCTestCase {
  func testGeminiErrorDescriptionDoesNotUseBackend() {
    let error = GeminiCorrector.GeminiError.requestFailed(404, nil)
    let description = error.errorDescription ?? ""
    XCTAssertFalse(description.contains("Backend"))
  }

  func testOpenRouterErrorDescriptionDoesNotUseBackend() {
    let error = OpenRouterCorrector.OpenRouterError.requestFailed(404, nil)
    let description = error.errorDescription ?? ""
    XCTAssertFalse(description.contains("Backend"))
  }

  func testOpenAIErrorDescriptionDoesNotUseBackend() {
    let error = OpenAICorrector.OpenAIError.requestFailed(404, nil)
    let description = error.errorDescription ?? ""
    XCTAssertFalse(description.contains("Backend"))
  }

  func testAnthropicErrorDescriptionDoesNotUseBackend() {
    let error = AnthropicCorrector.AnthropicError.requestFailed(404, nil)
    let description = error.errorDescription ?? ""
    XCTAssertFalse(description.contains("Backend"))
  }

  func testOpenAIRateLimitErrorDescription() {
    let error = OpenAICorrector.OpenAIError.requestFailed(429, nil)
    let description = error.errorDescription ?? ""
    let lower = description.lowercased()
    XCTAssertTrue(lower.contains("rate limit") || lower.contains("429"),
      "Expected rate limit or 429 in description, got: \(description)")
  }

  func testAnthropicRateLimitErrorDescription() {
    let error = AnthropicCorrector.AnthropicError.requestFailed(429, nil)
    let description = error.errorDescription ?? ""
    let lower = description.lowercased()
    XCTAssertTrue(lower.contains("rate limit") || lower.contains("429"),
      "Expected rate limit or 429 in description, got: \(description)")
  }

  func testAnthropicOverloadedErrorDescription() {
    let error = AnthropicCorrector.AnthropicError.requestFailed(529, nil)
    let description = error.errorDescription ?? ""
    let lower = description.lowercased()
    XCTAssertTrue(lower.contains("529") || lower.contains("overloaded"),
      "Expected 529 or overloaded in description, got: \(description)")
  }

  func testOpenAIUnauthorizedErrorDescription() {
    let error = OpenAICorrector.OpenAIError.requestFailed(401, nil)
    let description = error.errorDescription ?? ""
    let lower = description.lowercased()
    XCTAssertTrue(lower.contains("401") || lower.contains("unauthorized"),
      "Expected 401 or unauthorized in description, got: \(description)")
  }

  func testAnthropicUnauthorizedErrorDescription() {
    let error = AnthropicCorrector.AnthropicError.requestFailed(401, nil)
    let description = error.errorDescription ?? ""
    let lower = description.lowercased()
    XCTAssertTrue(lower.contains("401") || lower.contains("unauthorized"),
      "Expected 401 or unauthorized in description, got: \(description)")
  }

  func testOpenAIMissingApiKeyDescription() {
    let error = OpenAICorrector.OpenAIError.missingApiKey
    let description = error.errorDescription
    XCTAssertNotNil(description, "errorDescription should not be nil")
    XCTAssertFalse((description ?? "").isEmpty, "errorDescription should not be empty")
  }

  func testAnthropicMissingApiKeyDescription() {
    let error = AnthropicCorrector.AnthropicError.missingApiKey
    let description = error.errorDescription
    XCTAssertNotNil(description, "errorDescription should not be nil")
    XCTAssertFalse((description ?? "").isEmpty, "errorDescription should not be empty")
  }
}
