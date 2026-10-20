import XCTest
@testable import GrammarCorrection

final class OpenAITokenPolicyTests: XCTestCase {
  func testUsesMaxCompletionTokensForGPT41Mini() {
    XCTAssertTrue(OpenAITokenPolicy.usesMaxCompletionTokens(model: "gpt-4.1-mini"))
  }

  func testUsesMaxCompletionTokensForO3Model() {
    XCTAssertTrue(OpenAITokenPolicy.usesMaxCompletionTokens(model: "o3-mini"))
  }

  func testUsesMaxCompletionTokensForGPT5Model() {
    XCTAssertTrue(OpenAITokenPolicy.usesMaxCompletionTokens(model: "gpt-5-mini"))
  }

  func testUsesMaxTokensForLegacyGPT4Model() {
    XCTAssertFalse(OpenAITokenPolicy.usesMaxCompletionTokens(model: "gpt-4-turbo"))
  }

  func testUsesMaxTokensForGPT35Model() {
    XCTAssertFalse(OpenAITokenPolicy.usesMaxCompletionTokens(model: "gpt-3.5-turbo"))
  }

  func testReasoningEffortMinimalForBaseGPT5Family() {
    XCTAssertEqual(OpenAITokenPolicy.reasoningEffort(model: "gpt-5"), "minimal")
    XCTAssertEqual(OpenAITokenPolicy.reasoningEffort(model: "gpt-5-mini"), "minimal")
    XCTAssertEqual(OpenAITokenPolicy.reasoningEffort(model: " GPT-5-Nano "), "minimal")
    XCTAssertEqual(OpenAITokenPolicy.reasoningEffort(model: "gpt-5-nano-2025-08-07"), "minimal")
  }

  func testClarifyUsesLowReasoningEffort() {
    XCTAssertEqual(OpenAITokenPolicy.reasoningEffort(model: "gpt-5-nano", style: .clarify), "low")
    XCTAssertEqual(OpenAITokenPolicy.reasoningEffort(model: "gpt-5-nano", style: .minimal), "minimal")
    XCTAssertNil(OpenAITokenPolicy.reasoningEffort(model: "gpt-4.1-mini", style: .clarify))
  }

  func testReasoningEffortOmittedForOtherModels() {
    XCTAssertNil(OpenAITokenPolicy.reasoningEffort(model: "gpt-5.5"))
    XCTAssertNil(OpenAITokenPolicy.reasoningEffort(model: "gpt-5-chat-latest"))
    XCTAssertNil(OpenAITokenPolicy.reasoningEffort(model: "gpt-5-pro"))
    XCTAssertNil(OpenAITokenPolicy.reasoningEffort(model: "o3-mini"))
    XCTAssertNil(OpenAITokenPolicy.reasoningEffort(model: "gpt-4.1-mini"))
  }

  func testSupportsJSONModeOnlyForKnownModels() {
    XCTAssertTrue(OpenAITokenPolicy.supportsJSONMode(model: "gpt-5-nano"))
    XCTAssertTrue(OpenAITokenPolicy.supportsJSONMode(model: "gpt-4o-mini"))
    XCTAssertTrue(OpenAITokenPolicy.supportsJSONMode(model: "gpt-4.1"))
    XCTAssertTrue(OpenAITokenPolicy.supportsJSONMode(model: "o3-mini"))

    XCTAssertFalse(OpenAITokenPolicy.supportsJSONMode(model: "gpt-4"))
    XCTAssertFalse(OpenAITokenPolicy.supportsJSONMode(model: "o1-mini"))
    XCTAssertFalse(OpenAITokenPolicy.supportsJSONMode(model: "llama3"))
  }

  func testModelNormalization() {
    XCTAssertTrue(OpenAITokenPolicy.usesMaxCompletionTokens(model: "  GPT-4.1  "))
  }

  func testOmitsTemperatureForGPT5AndOModels() {
    XCTAssertTrue(OpenAITokenPolicy.omitsTemperature(model: "gpt-5-nano"))
    XCTAssertTrue(OpenAITokenPolicy.omitsTemperature(model: " o3-mini "))
  }

  func testKeepsTemperatureForLegacyChatModels() {
    XCTAssertFalse(OpenAITokenPolicy.omitsTemperature(model: "gpt-4-turbo"))
    XCTAssertFalse(OpenAITokenPolicy.omitsTemperature(model: "gpt-4.1-mini"))
  }
}
