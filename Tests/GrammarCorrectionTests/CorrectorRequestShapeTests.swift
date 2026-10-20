import XCTest

@testable import GrammarCorrection

/// Request-shape and retry-reason tests, split out to keep the main corrector test file short.
extension CorrectorRetryAndPlaceholderTests {
  func testGeminiFlashRequestDisablesThinking() async throws {
    var capturedBody: Data?

    MockURLProtocol.handler = { request in
      capturedBody = Self.requestBodyData(from: request)
      return Self.httpResponse(
        for: request,
        statusCode: 200,
        body: #"{"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}"#
      )
    }

    let settings = Settings(
      provider: .gemini,
      requestTimeoutSeconds: 1,
      geminiApiKey: "test-key",
      geminiBaseURL: "https://mock.local",
      geminiMaxAttempts: 1
    )
    let corrector = try GeminiCorrector(settings: settings, session: Self.makeMockSession())
    _ = try await corrector.correct("Hello")

    let body = try XCTUnwrap(capturedBody)
    let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let config = try XCTUnwrap(json["generationConfig"] as? [String: Any])
    let thinking = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
    XCTAssertEqual(thinking["thinkingBudget"] as? Int, 0)
    XCTAssertEqual(config["temperature"] as? Double, 0.0)
    XCTAssertEqual(config["maxOutputTokens"] as? Int, 4096)
  }

  func testAnthropicHaiku45RequestSetsZeroTemperature() async throws {
    let json = try await Self.captureAnthropicRequest(model: "claude-haiku-4-5")

    XCTAssertEqual(json["temperature"] as? Double, 0.0)
    XCTAssertNil(json["output_config"])
    XCTAssertEqual(json["max_tokens"] as? Int, 4096)
  }

  func testAnthropicHaiku55RequestUsesLowEffortWithoutTemperature() async throws {
    let json = try await Self.captureAnthropicRequest(model: "claude-haiku-5-5")

    XCTAssertNil(json["temperature"], "Haiku 5.5 rejects non-default temperature")
    let outputConfig = try XCTUnwrap(json["output_config"] as? [String: Any])
    XCTAssertEqual(outputConfig["effort"] as? String, "low")
  }

  func testRetryAfterRefusalSendsRefusalInstruction() async throws {
    let systems = try await Self.captureRetrySystemPrompts(
      input: "Hello there, my friend.",
      firstResponse: "I'm sorry, but I can't assist with that."
    )

    XCTAssertFalse(systems[0].contains("IMPORTANT: Your previous output"))
    XCTAssertTrue(systems[1].contains("was a refusal or a comment"))
  }

  func testRetryAfterDroppedPlaceholderSendsPlaceholderInstruction() async throws {
    let systems = try await Self.captureRetrySystemPrompts(
      input: "Check this link: https://example.com today",
      firstResponse: "Check this link: today"
    )

    XCTAssertTrue(systems[1].contains("dropped or changed a protected placeholder"))
  }

  func testRetryAfterTooLongOutputSendsLengthInstruction() async throws {
    let systems = try await Self.captureRetrySystemPrompts(
      input: "Hello there.",
      firstResponse: String(repeating: "Hello there. ", count: 8)
    )

    XCTAssertTrue(systems[1].contains("much longer than the original text"))
  }

  func testRetryAfterOverRewriteSendsOverRewriteInstruction() async throws {
    let systems = try await Self.captureRetrySystemPrompts(
      input: "Hello there, my friend.",
      firstResponse: "Totally unrelated words appear."
    )

    XCTAssertTrue(systems[1].contains("changed the text too much"))
  }

  /// Rejects the first response, echoes the protected input on the second, and returns both system prompts.
  private static func captureRetrySystemPrompts(input: String, firstResponse: String) async throws -> [String] {
    var systems: [String] = []

    MockURLProtocol.handler = { request in
      let body = try XCTUnwrap(Self.requestBodyData(from: request))
      let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
      let messages = json?["messages"] as? [[String: Any]]
      systems.append(messages?.first?["content"] as? String ?? "")

      let content = systems.count == 1
        ? firstResponse
        : Self.extractProtectedText(from: try Self.extractPrompt(from: request))
      let responseBody = """
      {"choices":[{"message":{"content":\(Self.jsonString(content))}}]}
      """
      return Self.httpResponse(for: request, statusCode: 200, body: responseBody)
    }

    let settings = Settings(
      provider: .openAI,
      requestTimeoutSeconds: 1,
      openAIApiKey: "test-key",
      openAIBaseURL: "https://mock.local",
      openAIMaxAttempts: 2
    )
    let corrector = try OpenAICorrector(settings: settings, session: Self.makeMockSession())
    let result = try await corrector.correct(input)

    XCTAssertEqual(result, input)
    XCTAssertEqual(systems.count, 2)
    return systems
  }

  private static func captureAnthropicRequest(model: String) async throws -> [String: Any] {
    var capturedBody: Data?

    MockURLProtocol.handler = { request in
      capturedBody = Self.requestBodyData(from: request)
      return Self.httpResponse(
        for: request,
        statusCode: 200,
        body: #"{"content":[{"type":"text","text":"Hello"}]}"#
      )
    }

    let settings = Settings(
      provider: .anthropic,
      requestTimeoutSeconds: 1,
      anthropicApiKey: "test-key",
      anthropicModel: model,
      anthropicBaseURL: "https://mock.local",
      anthropicMaxAttempts: 1
    )
    let corrector = try AnthropicCorrector(settings: settings, session: Self.makeMockSession())
    _ = try await corrector.correct("Hello")

    let body = try XCTUnwrap(capturedBody)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
  }
}
