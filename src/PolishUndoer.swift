import AppKit

/// What the last Polish replaced, and in which app.
struct PolishRecord: Equatable, Sendable {
  let original: String
  let polished: String
  let processID: pid_t?
  var style: CorrectionStyle = .clarify
}

/// Reads and selects text in the focused field of another app.
@MainActor
protocol FocusedTextAccess {
  func value(forProcess pid: pid_t) -> String?
  func selectedText(forProcess pid: pid_t) -> String?
  func select(_ range: NSRange, forProcess pid: pid_t) -> Bool
}

struct AccessibilityTextAccess: FocusedTextAccess {
  func value(forProcess pid: pid_t) -> String? {
    SelectionProbe.focusedValue(forProcess: pid)
  }

  func selectedText(forProcess pid: pid_t) -> String? {
    SelectionProbe.focusedSelectedText(forProcess: pid)
  }

  func select(_ range: NSRange, forProcess pid: pid_t) -> Bool {
    SelectionProbe.selectFocusedRange(range, forProcess: pid)
  }
}

/// Undo Last Polish: finds the exact text Polish pasted, selects it, and pastes the original back.
/// It never replaces anything else: if the polished text was edited or cannot be selected, it stops and says so.
@MainActor
final class PolishUndoer {
  private(set) var lastPolish: PolishRecord?
  private(set) var isRunning = false

  private let keyboard: KeyboardControlling
  private let pasteboard: PasteboardControlling
  private let feedback: FeedbackPresenter
  private let textAccess: FocusedTextAccess
  private let timings: CorrectionController.Timings
  private let frontmostApplicationPIDProvider: @MainActor () -> pid_t?
  private let activateApplication: @MainActor (pid_t) -> Void

  init(
    feedback: FeedbackPresenter,
    keyboard: KeyboardControlling? = nil,
    pasteboard: PasteboardControlling? = nil,
    textAccess: FocusedTextAccess? = nil,
    timings: CorrectionController.Timings = .default,
    frontmostApplicationPIDProvider: (@MainActor () -> pid_t?)? = nil,
    activateApplication: (@MainActor (pid_t) -> Void)? = nil
  ) {
    self.feedback = feedback
    self.keyboard = keyboard ?? KeyboardController()
    self.pasteboard = pasteboard ?? PasteboardController()
    self.textAccess = textAccess ?? AccessibilityTextAccess()
    self.timings = timings
    self.frontmostApplicationPIDProvider = frontmostApplicationPIDProvider ?? {
      NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    self.activateApplication = activateApplication ?? { pid in
      _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }
  }

  var canUndo: Bool {
    lastPolish?.processID != nil
  }

  func record(_ record: PolishRecord) {
    lastPolish = record
  }

  func undo() async {
    guard !isRunning else { return }
    guard let record = lastPolish, let pid = record.processID else {
      feedback.showInfo("Nothing to undo")
      return
    }
    isRunning = true
    defer { isRunning = false }

    guard await bringToFront(pid) else {
      fail("Couldn't switch back to the app that was polished")
      return
    }
    guard let value = textAccess.value(forProcess: pid) else {
      fail("Undo can't read this field. Use ⌘Z in the app instead.")
      return
    }
    let range = (value as NSString).range(of: record.polished, options: .backwards)
    guard range.location != NSNotFound else {
      fail("Can't undo: the polished text was changed")
      return
    }
    guard textAccess.select(range, forProcess: pid), textAccess.selectedText(forProcess: pid) == record.polished else {
      fail("This app doesn't let TextPolish select the text. Use ⌘Z instead.")
      return
    }

    let snapshot = pasteboard.snapshot()
    pasteboard.setString(record.original)
    let ownedChangeCount = pasteboard.changeCount
    try? await Task.sleep(for: timings.pasteSettleDelay)
    keyboard.sendCommandV()
    try? await Task.sleep(for: timings.postPasteDelay)
    if pasteboard.changeCount == ownedChangeCount {
      pasteboard.restore(snapshot)
    }

    lastPolish = nil
    TPLogger.log("Undo: restored chars=\(record.original.count)")
    feedback.showSuccess()
  }

  private func bringToFront(_ pid: pid_t) async -> Bool {
    guard frontmostApplicationPIDProvider() != pid else { return true }
    activateApplication(pid)
    for _ in 0..<10 where frontmostApplicationPIDProvider() != pid {
      try? await Task.sleep(for: max(timings.activationDelay, .milliseconds(20)))
    }
    return frontmostApplicationPIDProvider() == pid
  }

  private func fail(_ message: String) {
    TPLogger.log("Undo: \(message)")
    feedback.showError(message)
  }
}
