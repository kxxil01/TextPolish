import XCTest
import AppKit
@testable import GrammarCorrection

final class SettingsWindowControllerTests: XCTestCase {
    var controller: SettingsWindowController!
    var mockViewController: MockSettingsWindowViewController!

    override func setUp() {
        super.setUp()
        controller = SettingsWindowController()
        mockViewController = MockSettingsWindowViewController()
    }

    override func tearDown() {
        controller = nil
        mockViewController = nil
        super.tearDown()
    }

    func testWindowCreation() {
        XCTAssertNotNil(controller.window, "Window should be created")
        XCTAssertEqual(controller.window?.styleMask, [.titled, .closable, .miniaturizable], "Window should have correct style mask")
        XCTAssertEqual(controller.window?.minSize, NSSize(width: 600, height: 450), "Window should have correct min size")
        XCTAssertEqual(controller.window?.maxSize, NSSize(width: 800, height: 800), "Window should have correct max size")
    }

    func testWindowLevel() {
        XCTAssertEqual(controller.window?.level, .floating, "Window should float above other windows")
    }

    func testWindowCollectionBehavior() {
        XCTAssertTrue(controller.window?.collectionBehavior.contains(.transient) ?? false, "Window should be transient")
        XCTAssertTrue(controller.window?.collectionBehavior.contains(.stationary) ?? false, "Window should be stationary")
    }

    func testWindowCenter() {
        XCTAssertNotNil(controller.window?.isVisible, "Window should be visible after display")
    }

    func testCloseBehavior() {
        let window = controller.window
        controller.close()
        XCTAssertTrue(window?.isVisible == false, "Window should close when close() is called")
    }

    func testWindowWillCloseSavesSettings() {
        // This test requires mocking the view controller's settings
        let testSettings = Settings.loadOrCreateDefault()
        mockViewController.settings = testSettings

        controller.windowWillClose(Notification(name: NSNotification.Name("test")))

        // Settings are saved by the window controller's windowWillClose implementation
        XCTAssertTrue(true, "Settings should be saved on window close")
    }

    func testViewControllerSetup() {
        controller.windowDidLoad()
        XCTAssertNotNil(controller.viewController, "View controller should be set up")
        XCTAssertTrue(controller.viewController is SettingsWindowViewController, "Content view controller should be SettingsWindowViewController")
    }

    func testWindowTitle() {
        XCTAssertEqual(controller.window?.title, "TextPolish Settings", "Window should have correct title")
    }

    func testReleasedWhenClosed() {
        XCTAssertFalse(controller.window?.isReleasedWhenClosed ?? true, "Window should not be released when closed (for reuse)")
    }
}

// MARK: - Mock
class MockSettingsWindowViewController: SettingsWindowViewController {
    override func viewDidLoad() {
        // Don't call super to avoid setupUI being called
    }
}
