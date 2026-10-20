import XCTest
@testable import GrammarCorrection

final class ProviderRequestPolicyTests: XCTestCase {

  // MARK: - Gemini

  func testGemini25FlashDisablesThinkingAndKeepsZeroTemperature() {
    let config = GeminiRequestPolicy.generationConfig(model: "gemini-2.5-flash", maxOutputTokens: 2048)

    XCTAssertEqual(config.thinkingConfig, .init(thinkingBudget: 0, thinkingLevel: nil))
    XCTAssertEqual(config.temperature, 0.0)
    XCTAssertNil(config.responseMimeType)
  }

  func testGemini25FlashLiteWithModelsPrefixDisablesThinking() {
    let thinking = GeminiRequestPolicy.thinkingConfig(model: "models/gemini-2.5-flash-lite")

    XCTAssertEqual(thinking, .init(thinkingBudget: 0, thinkingLevel: nil))
  }

  func testGemini25ProUsesMinimumThinkingBudget() {
    XCTAssertEqual(
      GeminiRequestPolicy.thinkingConfig(model: "gemini-2.5-pro"),
      .init(thinkingBudget: 128, thinkingLevel: nil)
    )
    XCTAssertEqual(GeminiRequestPolicy.temperature(model: "gemini-2.5-pro"), 0.0)
  }

  func testGemini3FlashUsesMinimalThinkingAndDefaultTemperature() {
    let config = GeminiRequestPolicy.generationConfig(model: "gemini-3-flash", maxOutputTokens: 2048)

    XCTAssertEqual(config.thinkingConfig, .init(thinkingBudget: nil, thinkingLevel: "minimal"))
    XCTAssertNil(config.temperature, "Gemini 3 should use its default temperature")
  }

  func testGemini3ProUsesLowThinking() {
    let thinking = GeminiRequestPolicy.thinkingConfig(model: "gemini-3.1-pro-preview")

    XCTAssertEqual(thinking, .init(thinkingBudget: nil, thinkingLevel: "low"))
  }

  func testGeminiResponseMimeTypePassesThrough() {
    let config = GeminiRequestPolicy.generationConfig(
      model: "gemini-2.5-flash",
      maxOutputTokens: 1024,
      responseMimeType: "application/json"
    )

    XCTAssertEqual(config.responseMimeType, "application/json")
  }

  func testGeminiConfigOmitsNilFieldsWhenEncoded() throws {
    let config = GeminiRequestPolicy.generationConfig(model: "gemini-2.0-flash", maxOutputTokens: 512)
    let data = try JSONEncoder().encode(config)
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(Set(json.keys), ["temperature", "maxOutputTokens"])
  }

  // MARK: - Anthropic

  func testAnthropicTemperatureOnlyForModelsThatAcceptIt() {
    XCTAssertEqual(AnthropicRequestPolicy.temperature(model: "claude-haiku-4-5"), 0.0)
    XCTAssertEqual(AnthropicRequestPolicy.temperature(model: "claude-sonnet-4-6"), 0.0)
    XCTAssertEqual(AnthropicRequestPolicy.temperature(model: "claude-opus-4-6"), 0.0)
    XCTAssertEqual(AnthropicRequestPolicy.temperature(model: "claude-opus-4-20250514"), 0.0)
    XCTAssertEqual(AnthropicRequestPolicy.temperature(model: "claude-3-5-haiku-latest"), 0.0)

    XCTAssertNil(AnthropicRequestPolicy.temperature(model: "claude-opus-4-7"))
    XCTAssertNil(AnthropicRequestPolicy.temperature(model: "claude-opus-4-8"))
    XCTAssertNil(AnthropicRequestPolicy.temperature(model: "claude-sonnet-5-5"))
    XCTAssertNil(AnthropicRequestPolicy.temperature(model: "claude-haiku-5-5"))
    XCTAssertNil(AnthropicRequestPolicy.temperature(model: "claude-opus-5-5"))
  }

  func testAnthropicLowEffortOnlyForModelsThatThinkByDefault() {
    XCTAssertEqual(AnthropicRequestPolicy.effort(model: "claude-haiku-5-5"), "low")
    XCTAssertEqual(AnthropicRequestPolicy.effort(model: "claude-sonnet-5"), "low")
    XCTAssertEqual(AnthropicRequestPolicy.effort(model: "claude-opus-5-5"), "low")
    XCTAssertEqual(AnthropicRequestPolicy.effort(model: " Claude-Fable-5-1 "), "low")

    XCTAssertNil(AnthropicRequestPolicy.effort(model: "claude-haiku-4-5"))
    XCTAssertNil(AnthropicRequestPolicy.effort(model: "claude-opus-4-8"))
  }
}
