import AppKit
import XCTest

@testable import GrammarCorrection

@MainActor
final class DiagnosticsWindowTests: XCTestCase {
  private var window: DiagnosticsWindow!

  override func setUp() {
    super.setUp()
    _ = NSApplication.shared
    window = DiagnosticsWindow()
  }

  override func tearDown() {
    window.dismiss()
    window = nil
    super.tearDown()
  }

  func testWindowConfigurationSupportsFrontmostPresentation() {
    XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
    XCTAssertFalse(window.becomesKeyOnlyIfNeeded)
    XCTAssertFalse(window.hidesOnDeactivate)
    XCTAssertFalse(window.isReleasedWhenClosed)
    XCTAssertEqual(window.level, .floating)
    XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
    XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  func testShowMakesWindowVisibleAndDismissHidesIt() {
    window.show()

    XCTAssertTrue(window.isVisible)

    window.dismiss()

    XCTAssertFalse(window.isVisible)
  }
}
