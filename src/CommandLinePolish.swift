import Foundation

/// `TextPolish polish` and `TextPolish translate`: Polish from a terminal, a script, or the Shortcuts app
/// ("Run Shell Script" with the input passed to stdin). Uses the same settings, provider, and keys as the app.
enum CommandLinePolish {
  enum Action: Equatable {
    case polish
    case translate
  }

  enum Command: Equatable {
    /// `style` is a name from `--style`, or nil for the default style. `text` is nil when it comes from stdin.
    case run(Action, style: String?, text: String?)
    case help
  }

  enum Failure: Error, Equatable, LocalizedError {
    case usage(String)
    case unknownStyle(String)
    case noText

    var errorDescription: String? {
      switch self {
      case .usage(let message): return message
      case .unknownStyle(let name): return "Unknown style \"\(name)\". Use natural, minimal, shorter, formal, friendly, or custom."
      case .noText: return "No text to polish. Pass it as arguments or on stdin."
      }
    }
  }

  static let usage = """
    Usage:
      TextPolish polish [--style natural|minimal|shorter|formal|friendly|custom] [text]
      TextPolish translate [text]

    Without text, the text is read from stdin. The result is written to stdout.
    Uses the provider, model, and API key set in TextPolish Settings.

    Shortcuts app: add "Run Shell Script", set Pass Input to "to stdin", and run
      /Applications/TextPolish.app/Contents/MacOS/TextPolish polish --style formal
    """

  /// The command in `arguments` (without the program path), or nil when they are not a command,
  /// so the menu bar app starts as usual.
  static func parse(_ arguments: [String]) throws -> Command? {
    guard let first = arguments.first else { return nil }
    let action: Action
    switch first {
    case "polish": action = .polish
    case "translate": action = .translate
    case "help", "--help", "-h": return .help
    default: return nil
    }

    var style: String?
    var words: [String] = []
    var remaining = arguments.dropFirst()
    while let argument = remaining.popFirst() {
      switch argument {
      case "--style", "-s":
        guard action == .polish else { throw Failure.usage("translate has no --style option.") }
        guard let name = remaining.popFirst() else { throw Failure.usage("--style needs a style name.") }
        style = name
      case "--":
        words.append(contentsOf: remaining)
        remaining = []
      default:
        words.append(argument)
      }
    }
    return .run(action, style: style, text: words.isEmpty ? nil : words.joined(separator: " "))
  }

  /// The style a `--style` name asks for: a built-in style, "custom", or the Custom style's own name.
  static func correctionStyle(named name: String?, action: Action, settings: Settings) throws -> CorrectionStyle {
    if action == .translate {
      return .translateToEnglish
    }
    guard let name else {
      return settings.correctionStyle(for: settings.polishStyle)
    }
    let wanted = name.lowercased()
    let match = settings.availablePolishStyles.first {
      $0.rawValue == wanted || settings.displayName(for: $0).lowercased() == wanted
    }
    guard let match else { throw Failure.unknownStyle(name) }
    return settings.correctionStyle(for: match)
  }

  /// Runs a command and returns the exit status, or nil when the arguments are not a command.
  @MainActor
  static func runIfRequested(_ arguments: [String]) -> Int32? {
    do {
      guard let command = try parse(arguments) else { return nil }
      guard case .run(let action, let styleName, let givenText) = command else {
        print(usage)
        return 0
      }
      let settings = Settings.loadOrCreateDefault()
      let style = try correctionStyle(named: styleName, action: action, settings: settings)
      let text = givenText ?? readStandardInput()
      guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.noText }
      let corrector = CorrectorFactory.make(settings: settings)
      let output = try waitForCorrection(corrector: corrector, text: text, style: style)
      // A terminal gets a final newline; Shortcuts and pipes get the text exactly.
      FileHandle.standardOutput.write(Data((output + (isatty(STDOUT_FILENO) == 1 ? "\n" : "")).utf8))
      return 0
    } catch let failure as Failure {
      FileHandle.standardError.write(Data("\(failure.localizedDescription)\n\n\(usage)\n".utf8))
      return 2
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      FileHandle.standardError.write(Data("TextPolish: \(message)\n".utf8))
      return 1
    }
  }

  /// Stdin without its final newline, or nil when stdin is a terminal, so a bare command never waits for typing.
  private static func readStandardInput() -> String? {
    guard isatty(STDIN_FILENO) == 0 else { return nil }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard var text = String(data: data, encoding: .utf8) else { return nil }
    while text.hasSuffix("\n") {
      text.removeLast()
    }
    return text
  }

  /// Runs the correction off the main thread, where provider requests read the keychain, and waits for it.
  static func waitForCorrection(corrector: GrammarCorrector, text: String, style: CorrectionStyle) throws -> String {
    let result = ResultBox()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
      do {
        result.set(.success(try await corrector.correct(text, style: style)))
      } catch {
        result.set(.failure(error))
      }
      done.signal()
    }
    done.wait()
    return try result.get()
  }

  private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<String, Error> = .failure(CancellationError())

    func set(_ newValue: Result<String, Error>) {
      lock.withLock { value = newValue }
    }

    func get() throws -> String {
      try lock.withLock { value }.get()
    }
  }
}
