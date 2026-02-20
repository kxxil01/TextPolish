import XCTest
@testable import GrammarCorrection

final class ErrorLogSanitizerTests: XCTestCase {
  func testSanitizerRedactsApiKeysAndTruncates() {
    let raw = "authorization: Bearer sk-12345678901234567890 and x-api-key=sk-ant-abcdef1234567890 " + String(repeating: "x", count: 260)
    let sanitized = ErrorLogSanitizer.sanitize(raw)

    XCTAssertNotNil(sanitized)
    XCTAssertFalse(sanitized!.contains("1234567890"))
    XCTAssertFalse(sanitized!.contains("abcdef123"))
    XCTAssertLessThanOrEqual(sanitized!.count, 201)
  }
}
