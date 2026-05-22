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
