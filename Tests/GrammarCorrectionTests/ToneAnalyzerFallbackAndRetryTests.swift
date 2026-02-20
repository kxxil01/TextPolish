import XCTest
@testable import GrammarCorrection

final class ToneAnalyzerFallbackAndRetryTests: XCTestCase {
  override class func setUp() {
    super.setUp()
    URLProtocol.registerClass(ToneMockURLProtocol.self)
  }

  override class func tearDown() {
    URLProtocol.unregisterClass(ToneMockURLProtocol.self)
    super.tearDown()
  }

  override func tearDown() {
    ToneMockURLProtocol.handler = nil
    ToneMockURLProtocol.requestObserver = nil
    super.tearDown()
  }

  func testOpenAIToneAnalyzerRetriesOnServerError() async throws {
    var callCount = 0
    var timestamps: [Date] = []

    ToneMockURLProtocol.requestObserver = { _, date in
      timestamps.append(date)
    }

    ToneMockURLProtocol.handler = { request in
      callCount += 1
      if callCount == 1 {
        return Self.httpResponse(
          for: request,
          statusCode: 500,
          body: #"{"error":{"message":"server down"}}"#
        )
      }

      return Self.httpResponse(
        for: request,
        statusCode: 200,
        body: #"{"choices":[{"message":{"content":"{\"tone\":\"neutral\",\"sentiment\":\"neutral\",\"formality\":\"neutral\",\"explanation\":\"ok\"}"}}]}"#
      )
    }

    let settings = Settings(provider: .openAI, openAIApiKey: "test", openAIBaseURL: "https://mock.local")
    let analyzer = try OpenAIToneAnalyzer(settings: settings)
    _ = try await analyzer.analyze("This text is long enough.")

    XCTAssertEqual(timestamps.count, 2)
    XCTAssertGreaterThanOrEqual(timestamps[1].timeIntervalSince(timestamps[0]), 0.9)
  }

  func testAnthropicToneAnalyzerRetriesOnRateLimit() async throws {
    var callCount = 0
    var timestamps: [Date] = []

    ToneMockURLProtocol.requestObserver = { _, date in
      timestamps.append(date)
    }

    ToneMockURLProtocol.handler = { request in
      callCount += 1
      if callCount == 1 {
        return Self.httpResponse(
          for: request,
          statusCode: 429,
          body: #"{"error":{"message":"rate limited","retry_after":1}}"#,
          headers: ["Retry-After": "1"]
        )
      }

      return Self.httpResponse(
        for: request,
        statusCode: 200,
        body: #"{"content":[{"type":"text","text":"{\"tone\":\"neutral\",\"sentiment\":\"neutral\",\"formality\":\"neutral\",\"explanation\":\"ok\"}"}]}"#
      )
    }

    let settings = Settings(provider: .anthropic, anthropicApiKey: "test", anthropicBaseURL: "https://mock.local")
    let analyzer = try AnthropicToneAnalyzer(settings: settings)
    _ = try await analyzer.analyze("This text is long enough.")

    XCTAssertEqual(timestamps.count, 2)
    XCTAssertGreaterThanOrEqual(timestamps[1].timeIntervalSince(timestamps[0]), 0.9)
  }

  @MainActor
  func testToneAnalyzerFactoryFallbackGating() {
    let disabled = Settings(provider: .gemini, enableGeminiOpenRouterFallback: false)
    let enabled = Settings(provider: .gemini, enableGeminiOpenRouterFallback: true)

    let disabledAnalyzer = ToneAnalyzerFactory.make(settings: disabled)
    let enabledAnalyzer = ToneAnalyzerFactory.make(settings: enabled)

    XCTAssertFalse(disabledAnalyzer is FallbackToneAnalyzer)
    XCTAssertTrue(enabledAnalyzer is FallbackToneAnalyzer)
  }

  private static func httpResponse(
    for request: URLRequest,
    statusCode: Int,
    body: String,
    headers: [String: String] = ["Content-Type": "application/json"]
  ) -> (HTTPURLResponse, Data) {
    let data = body.data(using: .utf8) ?? Data()
    let response = HTTPURLResponse(
      url: request.url ?? URL(string: "https://mock.local")!,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: headers
    )!
    return (response, data)
  }
}

private final class ToneMockURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
  static var requestObserver: ((URLRequest, Date) -> Void)?

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "mock.local"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let now = Date()
    ToneMockURLProtocol.requestObserver?(request, now)

    guard let handler = ToneMockURLProtocol.handler else {
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
