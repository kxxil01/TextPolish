import AppKit

/// Practice: a short round built from the writer's own mistakes. Each question shows what they wrote before;
/// they type how they would write it now, then see the fix Learn mode explained.
@MainActor
final class PracticeWindow: NSPanel {
  private let history: LessonHistory
  private var quiz = PracticeQuiz(items: [])
  private let progressLabel = NSTextField(labelWithString: "")
  private let promptLabel = NSTextField(labelWithString: "How would you write this now?")
  private let phraseLabel = NSTextField(wrappingLabelWithString: "")
  private let answerField = NSTextField()
  private let resultLabel = NSTextField(wrappingLabelWithString: "")
  private let checkButton = NSButton(title: "Check", target: nil, action: nil)
  private let nextButton = NSButton(title: "Next", target: nil, action: nil)

  init(history: LessonHistory) {
    self.history = history
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    title = "Practice"
    isFloatingPanel = true
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    level = .floating
    setupUI()
  }

  /// Starts a new round from the latest lessons.
  func show() {
    startRound()
    center()
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
    makeFirstResponder(answerField)
  }

  private func startRound() {
    quiz = PracticeQuiz(items: history.practiceItems())
    showQuestion()
  }

  private func showQuestion() {
    resultLabel.stringValue = ""
    answerField.stringValue = ""
    guard let item = quiz.current else {
      showScore()
      return
    }
    progressLabel.stringValue = "Question \(quiz.index + 1) of \(quiz.items.count)"
    promptLabel.isHidden = false
    phraseLabel.stringValue = item.before
    answerField.isHidden = false
    answerField.isEnabled = true
    checkButton.isHidden = false
    checkButton.isEnabled = true
    checkButton.keyEquivalent = "\r"
    nextButton.isHidden = true
    nextButton.keyEquivalent = ""
    makeFirstResponder(answerField)
  }

  private func showScore() {
    progressLabel.stringValue = quiz.items.isEmpty ? "" : "Done"
    promptLabel.isHidden = true
    phraseLabel.stringValue = quiz.items.isEmpty
      ? "Nothing to practice yet. Turn on Learn in Settings > Advanced, then Polish some text."
      : "You got \(quiz.score) of \(quiz.items.count) right."
    answerField.isHidden = true
    checkButton.isHidden = true
    nextButton.isHidden = quiz.items.isEmpty
    nextButton.title = "Practice Again"
    nextButton.keyEquivalent = "\r"
  }

  @objc private func checkClicked() {
    guard let item = quiz.current else { return }
    let correct = quiz.check(answerField.stringValue)
    let reason = item.reason.map { ": \($0)" } ?? ""
    resultLabel.stringValue = correct ? "Correct\(reason)" : "Answer: \(item.after)\(reason)"
    resultLabel.textColor = correct ? .systemGreen : .systemOrange
    answerField.isEnabled = false
    checkButton.isEnabled = false
    checkButton.keyEquivalent = ""
    nextButton.title = quiz.index + 1 < quiz.items.count ? "Next" : "See Score"
    nextButton.isHidden = false
    nextButton.keyEquivalent = "\r"
  }

  @objc private func nextClicked() {
    if quiz.isFinished {
      startRound()
      return
    }
    quiz.next()
    showQuestion()
  }

  private func setupUI() {
    let container = NSView()
    contentView = container

    progressLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    progressLabel.textColor = .secondaryLabelColor
    promptLabel.font = .systemFont(ofSize: 13)
    promptLabel.textColor = .secondaryLabelColor
    phraseLabel.font = .systemFont(ofSize: 17, weight: .medium)
    phraseLabel.textColor = .systemRed
    answerField.placeholderString = "Type it the way you'd write it now"
    answerField.target = self
    answerField.action = #selector(checkClicked)
    answerField.setAccessibilityLabel("Your answer")
    resultLabel.font = .systemFont(ofSize: 13, weight: .medium)
    checkButton.target = self
    checkButton.action = #selector(checkClicked)
    checkButton.bezelStyle = .rounded
    nextButton.target = self
    nextButton.action = #selector(nextClicked)
    nextButton.bezelStyle = .rounded

    let buttons = NSStackView(views: [checkButton, nextButton])
    buttons.spacing = 8
    let stack = NSStackView(views: [progressLabel, promptLabel, phraseLabel, answerField, resultLabel, buttons])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
      answerField.widthAnchor.constraint(equalTo: stack.widthAnchor),
      phraseLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
      resultLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
  }

  #if DEBUG
    var debugPhrase: String {
      phraseLabel.stringValue
    }

    var debugResult: String {
      resultLabel.stringValue
    }

    var debugProgress: String {
      progressLabel.stringValue
    }

    func debugStartRound() {
      startRound()
    }

    func debugAnswer(_ answer: String) {
      answerField.stringValue = answer
      checkClicked()
    }

    func debugNext() {
      nextClicked()
    }
  #endif
}
