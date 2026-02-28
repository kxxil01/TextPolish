import XCTest
@testable import GrammarCorrection

final class ToneAnalyzerFallbackAndRetryTests: XCTestCase {
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

    let settings = Settings(
      provider: .openAI,
      requestTimeoutSeconds: 1,
      openAIApiKey: "test",
      openAIBaseURL: "https://mock.local"
    )
    let analyzer = try OpenAIToneAnalyzer(settings: settings, session: Self.makeMockSession())
    _ = try await analyzer.analyze("This text is long enough.")

    XCTAssertEqual(callCount, 2)
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

    let settings = Settings(
      provider: .anthropic,
      requestTimeoutSeconds: 1,
      anthropicApiKey: "test",
      anthropicBaseURL: "https://mock.local"
    )
    let analyzer = try AnthropicToneAnalyzer(settings: settings, session: Self.makeMockSession())
    _ = try await analyzer.analyze("This text is long enough.")

    XCTAssertEqual(callCount, 2)
    XCTAssertEqual(timestamps.count, 2)
    XCTAssertGreaterThanOrEqual(timestamps[1].timeIntervalSince(timestamps[0]), 0.9)
  }

  @MainActor
  func testToneAnalyzerFactoryFallbackGating() {
    let disabled = Settings(
      provider: .gemini,
      enableGeminiOpenRouterFallback: false,
      openRouterApiKey: "fallback-key"
    )
    let enabledWithCredentials = Settings(
      provider: .gemini,
      enableGeminiOpenRouterFallback: true,
      openRouterApiKey: "fallback-key"
    )

    let disabledAnalyzer = ToneAnalyzerFactory.make(settings: disabled)
    let enabledWithCredentialsAnalyzer = ToneAnalyzerFactory.make(settings: enabledWithCredentials)

    // When fallback is disabled, no FallbackToneAnalyzer should be created even with credentials
    XCTAssertFalse(disabledAnalyzer is FallbackToneAnalyzer)
    // When fallback is enabled and credentials exist, FallbackToneAnalyzer should be created
    XCTAssertTrue(enabledWithCredentialsAnalyzer is FallbackToneAnalyzer)

    // "Without credentials" case: only assert if Keychain doesn't have an OpenRouter key,
    // since the factory also checks Keychain which we can't mock in integration tests.
    let keychainService = Bundle.main.bundleIdentifier ?? "com.kxxil01.TextPolish"
    let hasKeychainKey = ((try? Keychain.getPassword(service: keychainService, account: "openRouterApiKey"))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty == false
    let hasLegacyKey = ((try? Keychain.getPassword(service: "com.ilham.GrammarCorrection", account: "openRouterApiKey"))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty == false

    if !hasKeychainKey && !hasLegacyKey {
      let enabledWithoutCredentials = Settings(provider: .gemini, enableGeminiOpenRouterFallback: true)
      let enabledWithoutCredentialsAnalyzer = ToneAnalyzerFactory.make(settings: enabledWithoutCredentials)
      XCTAssertFalse(enabledWithoutCredentialsAnalyzer is FallbackToneAnalyzer)
    }
  }

  private static func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ToneMockURLProtocol.self]
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForRequest = 1
    configuration.timeoutIntervalForResource = 1
    return URLSession(configuration: configuration)
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
