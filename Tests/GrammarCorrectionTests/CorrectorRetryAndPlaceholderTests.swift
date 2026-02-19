import XCTest

@testable import GrammarCorrection

final class CorrectorRetryAndPlaceholderTests: XCTestCase {
  override class func setUp() {
    super.setUp()
    URLProtocol.registerClass(MockURLProtocol.self)
  }

  override class func tearDown() {
    URLProtocol.unregisterClass(MockURLProtocol.self)
    super.tearDown()
  }

  override func tearDown() {
    MockURLProtocol.handler = nil
    MockURLProtocol.requestObserver = nil
    super.tearDown()
  }

  func testOpenAIRetrySleepsOnNon429Error() async throws {
    var timestamps: [Date] = []
    var callCount = 0

    MockURLProtocol.requestObserver = { _, date in
      timestamps.append(date)
    }

    MockURLProtocol.handler = { request in
      callCount += 1
      if callCount == 1 {
        return Self.httpResponse(
          for: request,
          statusCode: 500,
          body: #"{"error":{"message":"server error"}}"#
        )
      }

      return Self.httpResponse(
        for: request,
        statusCode: 200,
        body: #"{"choices":[{"message":{"content":"Hello"}}]}"#
      )
    }

    let settings = Settings(
      provider: .openAI,
      openAIApiKey: "test-key",
      openAIBaseURL: "https://mock.local",
      openAIMaxAttempts: 1
    )
    let corrector = try OpenAICorrector(settings: settings)
    let result = try await corrector.correct("Hello")

    XCTAssertEqual(result, "Hello")
    XCTAssertEqual(timestamps.count, 2, "Expected two network attempts")
    let delay = timestamps[1].timeIntervalSince(timestamps[0])
    XCTAssertGreaterThanOrEqual(delay, 0.9, "Expected retry delay before second attempt")
  }

  func testAnthropicRetrySleepsOnNon429Error() async throws {
    var timestamps: [Date] = []
    var callCount = 0

    MockURLProtocol.requestObserver = { _, date in
      timestamps.append(date)
    }

    MockURLProtocol.handler = { request in
      callCount += 1
      if callCount == 1 {
        return Self.httpResponse(
          for: request,
          statusCode: 500,
          body: #"{"error":{"message":"server error"}}"#
        )
      }

      return Self.httpResponse(
        for: request,
        statusCode: 200,
        body: #"{"content":[{"type":"text","text":"Hello"}]}"#
      )
    }

    let settings = Settings(
      provider: .anthropic,
      anthropicApiKey: "test-key",
      anthropicBaseURL: "https://mock.local",
      anthropicMaxAttempts: 1
    )
    let corrector = try AnthropicCorrector(settings: settings)
    let result = try await corrector.correct("Hello")

    XCTAssertEqual(result, "Hello")
    XCTAssertEqual(timestamps.count, 2, "Expected two network attempts")
    let delay = timestamps[1].timeIntervalSince(timestamps[0])
    XCTAssertGreaterThanOrEqual(delay, 0.9, "Expected retry delay before second attempt")
  }

  func testOpenAIPlaceholderProtectionPreservesText() async throws {
    MockURLProtocol.handler = { request in
      let prompt = try Self.extractPrompt(from: request)
      let protectedText = Self.extractProtectedText(from: prompt)
      let body = """
      {"choices":[{"message":{"content":\(Self.jsonString(protectedText))}}]}
      """
      return Self.httpResponse(for: request, statusCode: 200, body: body)
    }

    let settings = Settings(
      provider: .openAI,
      openAIApiKey: "test-key",
      openAIBaseURL: "https://mock.local",
      openAIMaxAttempts: 1
    )
    let corrector = try OpenAICorrector(settings: settings)
    let input = "Check this link: https://example.com and <@123>"
    let result = try await corrector.correct(input)

    XCTAssertEqual(result, input)
  }

  func testAnthropicPlaceholderProtectionPreservesText() async throws {
    MockURLProtocol.handler = { request in
      let prompt = try Self.extractPrompt(from: request)
      let protectedText = Self.extractProtectedText(from: prompt)
      let body = """
      {"content":[{"type":"text","text":\(Self.jsonString(protectedText))}]}
      """
      return Self.httpResponse(for: request, statusCode: 200, body: body)
    }

    let settings = Settings(
      provider: .anthropic,
      anthropicApiKey: "test-key",
      anthropicBaseURL: "https://mock.local",
      anthropicMaxAttempts: 1
    )
    let corrector = try AnthropicCorrector(settings: settings)
    let input = "Check this link: https://example.com and <@123>"
    let result = try await corrector.correct(input)

    XCTAssertEqual(result, input)
  }

  private static func extractPrompt(from request: URLRequest) throws -> String {
    guard let body = request.httpBody else { return "" }
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let messages = json?["messages"] as? [[String: Any]]
    return messages?.first?["content"] as? String ?? ""
  }

  private static func extractProtectedText(from prompt: String) -> String {
    if let range = prompt.range(of: "\nTEXT:\n") {
      return String(prompt[range.upperBound...])
    }
    if let range = prompt.range(of: "TEXT:\n") {
      return String(prompt[range.upperBound...])
    }
    return prompt
  }

  private static func jsonString(_ value: String) -> String {
    let data = try? JSONEncoder().encode(value)
    let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    return encoded
  }

  private static func httpResponse(for request: URLRequest, statusCode: Int, body: String) -> (HTTPURLResponse, Data) {
    let data = body.data(using: .utf8) ?? Data()
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://mock.local")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
  }
}

private final class MockURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  static var requestObserver: ((URLRequest, Date) -> Void)?

  override class func canInit(with request: URLRequest) -> Bool {
    guard let host = request.url?.host else { return false }
    return host == "mock.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let now = Date()
    MockURLProtocol.requestObserver?(request, now)

    guard let handler = MockURLProtocol.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
