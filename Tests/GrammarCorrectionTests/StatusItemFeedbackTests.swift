import XCTest
import AppKit

@testable import GrammarCorrection

final class StatusItemFeedbackTests: XCTestCase {
  private final class TestSleeper {
    private(set) var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var durations: [Duration] = []

    func sleep(_ duration: Duration) async {
      durations.append(duration)
      await withCheckedContinuation { continuation in
        continuations.append(continuation)
      }
    }

    func resumeAll() {
      while !continuations.isEmpty {
        continuations.removeFirst().resume()
      }
    }
  }

  @MainActor
  func testFlashUpdatesButtonState() async throws {
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

    // Show success - button should immediately show checkmark
    feedback.showSuccess()

    // Button should show the success state immediately (before sleep completes)
    XCTAssertEqual(button.title, "\u{2713}")
    XCTAssertEqual(button.toolTip, "Corrected")

    // Verify sleepHandler was called with expected duration
    // Give it a moment to schedule the task
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertEqual(sleeper.durations.count, 1)
    XCTAssertEqual(sleeper.durations.first, .milliseconds(800))
  }

  @MainActor
  func testOverlappingFlashesCancelsPrevious() async throws {
    let environment = ProcessInfo.processInfo.environment
    if environment["GITHUB_ACTIONS"] != nil || environment["CI"] != nil {
      throw XCTSkip("Status bar unavailable on CI runners.")
    }

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    defer { NSStatusBar.system.removeStatusItem(statusItem) }

    guard let button = statusItem.button else {
      throw XCTSkip("Status item button unavailable on this runner.")
    }

    let baseImage = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: nil)
    button.image = baseImage

    let sleeper = TestSleeper()
    let feedback = StatusItemFeedback(
      statusItem: statusItem,
      baseImage: baseImage,
      sleepHandler: sleeper.sleep
    )

    // Show info then immediately show success
    feedback.showInfo("Info")
    feedback.showSuccess()

    // Button should show the LAST flash state (success)
    XCTAssertEqual(button.title, "\u{2713}")
    XCTAssertEqual(button.toolTip, "Corrected")
  }
}
