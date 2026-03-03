import XCTest
import AppKit
@testable import GrammarCorrection

@MainActor
final class ToneAnalysisResultWindowTests: XCTestCase {
    private var window: ToneAnalysisResultWindow!

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        window = ToneAnalysisResultWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    override func tearDown() {
        window.dismiss()
        window = nil
        super.tearDown()
    }

    func testEscapeMonitorIsReinstalledAfterDismiss() {
        XCTAssertFalse(window.hasActiveEscapeMonitor, "Monitor should not be active before first presentation")

        window.showError("Test error")
        XCTAssertTrue(window.hasActiveEscapeMonitor, "Monitor should be active while result window is visible")

        window.dismiss()
        XCTAssertFalse(window.hasActiveEscapeMonitor, "Monitor should be removed when window is dismissed")

        window.showResult(
            ToneAnalysisResult(
                tone: .neutral,
                sentiment: .neutral,
                formality: .casual,
                explanation: "Test"
            )
        )
        XCTAssertTrue(window.hasActiveEscapeMonitor, "Monitor should be restored when showing the window again")
    }
}
