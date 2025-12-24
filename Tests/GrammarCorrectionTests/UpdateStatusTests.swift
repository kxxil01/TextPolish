import XCTest

@testable import GrammarCorrection

final class UpdateStatusTests: XCTestCase {
  func testMenuTitleValues() {
    XCTAssertEqual(UpdateStatus.unknown.menuTitle, "Update status: Unknown")
    XCTAssertEqual(UpdateStatus.checking.menuTitle, "Update status: Checking...")
    XCTAssertEqual(UpdateStatus.available.menuTitle, "Update status: Update available")
    XCTAssertEqual(UpdateStatus.upToDate.menuTitle, "Update status: Up to date")
    XCTAssertEqual(UpdateStatus.message("Custom").menuTitle, "Update status: Custom")
  }
}
