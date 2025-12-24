import XCTest
import AppKit

@testable import GrammarCorrection

final class StatusItemFeedbackTests: XCTestCase {
  private final class TestSleeper {
    private(set) var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
      await withCheckedContinuation { continuation in
        continuations.append(continuation)
      }
    }

    func resumeNext() {
      guard !continuations.isEmpty else { return }
      continuations.removeFirst().resume()
    }
  }

  @MainActor
  func testOverlappingFlashesRestoreBaseState() async throws {
    let environment = ProcessInfo.processInfo.environment
    if environment["GITHUB_ACTIONS"] != nil || environment["CI"] != nil {
      throw XCTSkip("Status bar unavailable on CI runners.")
    }

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    defer { NSStatusBar.system.removeStatusItem(statusItem) }

    guard let button = statusItem.button else {
      throw XCTSkip("Status item button unavailable on this runner.")
    }

    button.title = "Base"
    button.toolTip = "BaseTip"
    let baseImage = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: nil)
    button.image = baseImage

    let sleeper = TestSleeper()
    let feedback = StatusItemFeedback(
      statusItem: statusItem,
      baseImage: baseImage,
      sleepHandler: sleeper.sleep
    )

    feedback.showInfo("Info")
    await Task.yield()

    feedback.showSuccess()
    await Task.yield()

    XCTAssertEqual(sleeper.continuations.count, 2)

    sleeper.resumeNext()
    await Task.yield()
    XCTAssertEqual(button.title, "\u{2713}")

    sleeper.resumeNext()
    await Task.yield()
    XCTAssertEqual(button.title, "Base")
    XCTAssertEqual(button.toolTip, "BaseTip")
  }
}
