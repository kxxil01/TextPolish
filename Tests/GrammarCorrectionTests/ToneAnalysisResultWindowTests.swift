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
                plainMeaning: "Test meaning",
                likelyIntent: "Test intent",
                sentiment: .neutral,
                formality: .casual,
                keyPhrases: [KeyPhrase(phrase: "no worries", meaning: "It's okay, don't be concerned")],
                misunderstandingRisk: MisunderstandingRisk(level: .low, reason: "Clear"),
                ambiguities: ["Phrase A can mean X or Y"],
                suggestedReplies: ["Can you clarify which one you mean?"]
            )
        )
        XCTAssertTrue(window.hasActiveEscapeMonitor, "Monitor should be restored when showing the window again")
    }
}
