import AppKit
import XCTest

@testable import GrammarCorrection

/// Undo Last Polish only ever replaces the exact text Polish pasted.
final class PolishUndoerTests: XCTestCase {
  typealias Stubs = CorrectionControllerTests

  @MainActor
  final class StubTextAccess: FocusedTextAccess {
    var value: String?
    var allowsSelection = true
    private(set) var selectedRange: NSRange?

    init(value: String?) {
      self.value = value
    }

    func value(forProcess _: pid_t) -> String? {
      value
    }

    func selectedText(forProcess _: pid_t) -> String? {
      guard let value, let selectedRange else { return nil }
      return (value as NSString).substring(with: selectedRange)
    }

    func select(_ range: NSRange, forProcess _: pid_t) -> Bool {
      guard allowsSelection else { return false }
      selectedRange = range
      return true
    }
  }

  private let record = PolishRecord(original: "pls refer to this", polished: "Please see this.", processID: 101)

  struct Harness {
    let undoer: PolishUndoer
    let feedback: Stubs.StubFeedback
    let keyboard: Stubs.StubKeyboard
    let pasteboard: Stubs.StubPasteboard
  }

  @MainActor
  private func makeUndoer(
    textAccess: StubTextAccess,
    frontmost: @escaping @MainActor () -> pid_t? = { 101 },
    activate: @escaping @MainActor (pid_t) -> Void = { _ in }
  ) -> Harness {
    let feedback = Stubs.StubFeedback()
    let keyboard = Stubs.StubKeyboard(isTrusted: true)
    let pasteboard = Stubs.StubPasteboard()
    let undoer = PolishUndoer(
      feedback: feedback,
      keyboard: keyboard,
      pasteboard: pasteboard,
      textAccess: textAccess,
      timings: Stubs.fastTimings,
      frontmostApplicationPIDProvider: frontmost,
      activateApplication: activate
    )
    return Harness(undoer: undoer, feedback: feedback, keyboard: keyboard, pasteboard: pasteboard)
  }

  @MainActor
  func testUndoSelectsThePolishedTextAndPastesTheOriginal() async {
    let access = StubTextAccess(value: "Hi Sam,\nPlease see this. Thanks")
    let harness = makeUndoer(textAccess: access)
    let (undoer, feedback, keyboard, pasteboard) = (harness.undoer, harness.feedback, harness.keyboard, harness.pasteboard)
    undoer.record(record)

    await undoer.undo()

    XCTAssertEqual(access.selectedRange, NSRange(location: 8, length: 16))
    XCTAssertEqual(pasteboard.setStringCalls, ["pls refer to this"])
    XCTAssertEqual(keyboard.commandVCount, 1)
    XCTAssertEqual(pasteboard.restoreCallCount, 1, "The clipboard goes back to what it held")
    XCTAssertEqual(feedback.successCount, 1)
    XCTAssertNil(undoer.lastPolish, "One undo per Polish")
  }

  @MainActor
  func testEditedTextIsLeftAlone() async {
    let access = StubTextAccess(value: "Please see this, it changed.")
    let harness = makeUndoer(textAccess: access)
    let (undoer, feedback, keyboard, pasteboard) = (harness.undoer, harness.feedback, harness.keyboard, harness.pasteboard)
    undoer.record(record)

    await undoer.undo()

    XCTAssertEqual(keyboard.commandVCount, 0)
    XCTAssertTrue(pasteboard.setStringCalls.isEmpty)
    XCTAssertEqual(feedback.errorMessages, ["Can't undo: the polished text was changed"])
    XCTAssertEqual(undoer.lastPolish, record, "Still available if the text is restored")
  }

  @MainActor
  func testAppsThatRefuseSelectionAreLeftAlone() async {
    let access = StubTextAccess(value: "Please see this.")
    access.allowsSelection = false
    let harness = makeUndoer(textAccess: access)
    let (undoer, feedback, keyboard) = (harness.undoer, harness.feedback, harness.keyboard)
    undoer.record(record)

    await undoer.undo()

    XCTAssertEqual(keyboard.commandVCount, 0)
    XCTAssertEqual(feedback.errorMessages, ["This app doesn't let TextPolish select the text. Use ⌘Z instead."])
  }

  @MainActor
  func testUnreadableFieldsAreLeftAlone() async {
    let harness = makeUndoer(textAccess: StubTextAccess(value: nil))
    let (undoer, feedback, keyboard) = (harness.undoer, harness.feedback, harness.keyboard)
    undoer.record(record)

    await undoer.undo()

    XCTAssertEqual(keyboard.commandVCount, 0)
    XCTAssertEqual(feedback.errorMessages, ["Undo can't read this field. Use ⌘Z in the app instead."])
  }

  @MainActor
  func testSwitchesBackToThePolishedAppFirst() async {
    var frontmost: pid_t = 202
    var activations: [pid_t] = []
    let access = StubTextAccess(value: "Please see this.")
    let harness = makeUndoer(
      textAccess: access,
      frontmost: { frontmost },
      activate: { pid in
        activations.append(pid)
        frontmost = pid
      }
    )
    harness.undoer.record(record)

    await harness.undoer.undo()

    XCTAssertEqual(activations, [101])
    XCTAssertEqual(harness.keyboard.commandVCount, 1)
  }

  @MainActor
  func testNothingToUndo() async {
    let harness = makeUndoer(textAccess: StubTextAccess(value: "x"))
    let (undoer, feedback, keyboard) = (harness.undoer, harness.feedback, harness.keyboard)

    await undoer.undo()

    XCTAssertFalse(undoer.canUndo)
    XCTAssertEqual(feedback.infoMessages, ["Nothing to undo"])
    XCTAssertEqual(keyboard.commandVCount, 0)
  }

  @MainActor
  func testMenuItemIsEnabledAfterAPolish() throws {
    _ = NSApplication.shared
    UserDefaults.standard.set(true, forKey: "didShowWelcome_0_1")
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let delegate = AppDelegate()
    delegate.debugFinishLaunching()
    XCTAssertFalse(delegate.debugUndoEnabled)

    delegate.debugRecordPolish(record)

    XCTAssertTrue(delegate.debugUndoEnabled)
  }
}

extension CorrectionControllerTests {
  @MainActor
  func testPolishRecordsTheTargetAppForUndo() async {
    let finished = expectation(description: "polish finished")
    var records: [PolishRecord] = []
    let controller = CorrectionController(
      corrector: UndoExclaimingCorrector(),
      feedback: StubFeedback(),
      settings: Settings(),
      timings: Self.fastTimings,
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success("hello")]),
      frontmostApplicationPIDProvider: { 4242 },
      onPolished: { record in
        records.append(record)
        finished.fulfill()
      }
    )

    controller.polish(style: .minimal)

    await fulfillment(of: [finished], timeout: 1.0)
    XCTAssertEqual(records, [PolishRecord(original: "hello", polished: "hello!", processID: 4242)])
  }
}

private struct UndoExclaimingCorrector: GrammarCorrector {
  func correct(_ text: String) async throws -> String {
    text + "!"
  }
}
