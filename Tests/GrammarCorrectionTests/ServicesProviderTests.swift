import AppKit
import XCTest

@testable import GrammarCorrection

/// Right-click > Services runs Polish or Translate on the text macOS hands over.
final class ServicesProviderTests: XCTestCase {
  @MainActor
  func testEachServicePassesItsActionAndTheSelectedText() {
    var requests: [(ServicesProvider.Action, String)] = []
    let provider = ServicesProvider { requests.append(($0, $1)) }
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("TextPolishServicesTest-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("pls check", forType: .string)
    var error: NSString?

    provider.polishService(pasteboard, userData: nil, error: &error)
    provider.translateService(pasteboard, userData: nil, error: &error)

    XCTAssertNil(error)
    XCTAssertEqual(requests.map(\.0), [.polish, .translate])
    XCTAssertEqual(requests.map(\.1), ["pls check", "pls check"])
  }

  @MainActor
  func testBlankSelectionReportsAnErrorAndRunsNothing() {
    var requests = 0
    let provider = ServicesProvider { _, _ in requests += 1 }
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("TextPolishServicesTest-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.setString("  \n", forType: .string)
    var error: NSString?

    provider.polishService(pasteboard, userData: nil, error: &error)

    XCTAssertEqual(error, "No text selected")
    XCTAssertEqual(requests, 0)
  }

  /// The Info.plist entries name these selectors; a rename on either side would silently drop the menu items.
  @MainActor
  func testInfoPlistDeclaresBothServicesAndTheProviderAnswersThem() throws {
    let script = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("scripts/build_app.sh")
    let contents = try String(contentsOf: script, encoding: .utf8)
    let provider = ServicesProvider { _, _ in }

    for message in ["polishService", "translateService"] {
      XCTAssertTrue(contents.contains("<string>\(message)</string>"), message)
      XCTAssertTrue(provider.responds(to: NSSelectorFromString("\(message):userData:error:")), message)
    }
    XCTAssertTrue(contents.contains("<string>Polish with ${APP_NAME}</string>"))
    XCTAssertTrue(contents.contains("<string>Translate to English with ${APP_NAME}</string>"))
    XCTAssertTrue(contents.contains("<key>NSRequiredContext</key>"), "Without it macOS leaves the services off")
  }

  @MainActor
  func testAppRegistersItselfAsTheServicesProvider() throws {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()

    XCTAssertTrue(NSApp.servicesProvider as AnyObject === delegate.debugServicesProvider)
  }
}

extension CorrectionControllerTests {
  @MainActor
  func testHandedOverTextIsPolishedWithoutCopying() async {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onSuccess = { finished.fulfill() }
    let keyboard = StubKeyboard(isTrusted: true)
    let pasteboard = StubPasteboard(waitResults: [])
    let controller = CorrectionController(
      corrector: ServiceExclaimingCorrector(),
      feedback: feedback,
      settings: Settings(),
      timings: Self.fastTimings,
      keyboard: keyboard,
      pasteboard: pasteboard
    )

    controller.polish(style: .minimal, text: "hello")

    await fulfillment(of: [finished], timeout: 1.0)
    XCTAssertEqual(keyboard.commandCCount, 0, "macOS already handed over the selection")
    XCTAssertEqual(keyboard.commandACount, 0)
    XCTAssertEqual(keyboard.commandVCount, 1)
    XCTAssertTrue(pasteboard.setStringCalls.contains("hello!"))
    XCTAssertEqual(pasteboard.restoreCallCount, 1, "The clipboard goes back to what it held")
  }
}

private struct ServiceExclaimingCorrector: GrammarCorrector {
  func correct(_ text: String) async throws -> String {
    text + "!"
  }
}
