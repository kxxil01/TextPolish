import XCTest

@testable import GrammarCorrection

final class DiagnosticsStoreTests: XCTestCase {
  @MainActor
  func testFormattedSnapshotIncludesHealthRecentActivityAndLastError() {
    let store = DiagnosticsStore()

    store.recordFailure(
      operation: .correction,
      provider: .gemini,
      model: "gemini-2.0-flash-lite-001",
      latencySeconds: 1.2,
      retryCount: 2,
      fallbackCount: 0,
      message: "Network offline",
      error: URLError(.notConnectedToInternet)
    )

    let text = store.formattedSnapshot()

    XCTAssertTrue(text.contains("Provider Health"))
    XCTAssertTrue(text.contains("State: Degraded"))
    XCTAssertTrue(text.contains("Message: Network error"))
    XCTAssertTrue(text.contains("Recent Activity"))
    XCTAssertTrue(text.contains("Result: Error"))
    XCTAssertTrue(text.contains("Error: Network offline"))
    XCTAssertTrue(text.contains("Last Error"))
  }

  @MainActor
  func testLastFailureSnapshotIsRetainedAfterSuccess() {
    let store = DiagnosticsStore()

    store.recordFailure(
      operation: .correction,
      provider: .openAI,
      model: "gpt-5-nano",
      latencySeconds: 0.4,
      retryCount: 0,
      fallbackCount: 0,
      message: "Request failed",
      error: URLError(.timedOut)
    )

    store.recordSuccess(
      operation: .toneAnalysis,
      provider: .openAI,
      model: "gpt-5-nano",
      latencySeconds: 0.2,
      retryCount: 1,
      fallbackCount: 0
    )

    XCTAssertEqual(store.lastSnapshot?.status, .success)
    XCTAssertEqual(store.lastFailureSnapshot?.status, .error)
    XCTAssertEqual(store.lastFailureSnapshot?.message, "Request failed")

    let text = store.formattedSnapshot()
    XCTAssertTrue(text.contains("Provider Health"))
    XCTAssertTrue(text.contains("State: OK"))
    XCTAssertTrue(text.contains("Recent Activity"))
    XCTAssertTrue(text.contains("Operation: Tone Analysis"))
    XCTAssertTrue(text.contains("Result: Success"))
    XCTAssertTrue(text.contains("Last Error"))
    XCTAssertTrue(text.contains("Operation: Correction"))
    XCTAssertTrue(text.contains("Error: Request failed"))
  }

  @MainActor
  func testFormattedSnapshotHandlesEmptyState() {
    let store = DiagnosticsStore()
    let text = store.formattedSnapshot()

    XCTAssertTrue(text.contains("Provider Health"))
    XCTAssertTrue(text.contains("State: Unknown"))
    XCTAssertTrue(text.contains("Recent Activity"))
    XCTAssertTrue(text.contains("No activity recorded yet."))
    XCTAssertTrue(text.contains("Last Error"))
    XCTAssertTrue(text.contains("No errors recorded."))
  }
}
