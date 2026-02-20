import XCTest
@testable import GrammarCorrection

final class RetryAfterParserTests: XCTestCase {
  func testParsesIntegerRetryAfterHeader() {
    let response = httpResponse(headers: ["Retry-After": "7"])
    let seconds = RetryAfterParser.retryAfterSeconds(from: response, data: Data())

    XCTAssertEqual(seconds, 7)
  }

  func testParsesDecimalRetryAfterHeaderByTruncatingFraction() {
    let response = httpResponse(headers: ["Retry-After": "7.9"])
    let seconds = RetryAfterParser.retryAfterSeconds(from: response, data: Data())

    XCTAssertEqual(seconds, 7)
  }

  func testParsesHTTPDateRetryAfterHeader() {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"

    let retryDate = Date().addingTimeInterval(2)
    let headerValue = formatter.string(from: retryDate)
    let response = httpResponse(headers: ["Retry-After": headerValue])

    let seconds = RetryAfterParser.retryAfterSeconds(from: response, data: Data())

    XCTAssertNotNil(seconds)
    XCTAssertGreaterThanOrEqual(seconds ?? 0, 1)
    XCTAssertLessThanOrEqual(seconds ?? 0, 4)
  }

  func testMalformedRetryAfterHeaderDefaultsToFiveSeconds() {
    let response = httpResponse(headers: ["Retry-After": "not-a-valid-retry-after"])
    let seconds = RetryAfterParser.retryAfterSeconds(from: response, data: Data())

    XCTAssertEqual(seconds, 5)
  }

  func testParsesDecimalRetryAfterFromBody() {
    let body = Data(#"{"error":{"retry_after":"12.8"}}"#.utf8)

    let seconds = RetryAfterParser.extractRetryAfter(from: body)

    XCTAssertEqual(seconds, 12)
  }

  func testMalformedRetryAfterInBodyDefaultsToFiveSeconds() {
    let body = Data(#"{"error":{"retry_after":"tomorrow"}}"#.utf8)

    let seconds = RetryAfterParser.extractRetryAfter(from: body)

    XCTAssertEqual(seconds, 5)
  }

  private func httpResponse(headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 429, httpVersion: nil, headerFields: headers)!
  }
}
