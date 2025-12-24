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
}
