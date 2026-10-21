import XCTest

@testable import GrammarCorrection

/// Sends real Polish prompts to a real provider so prompt regressions show up before a release.
/// Skipped unless TEXTPOLISH_LIVE_CHECKS=1, so CI never calls a provider. A run costs a few cents.
///
///     TEXTPOLISH_LIVE_CHECKS=1 OPENAI_API_KEY=sk-... swift test --filter LivePromptChecks
///
/// Optional: TEXTPOLISH_LIVE_PROVIDER (openai, gemini, anthropic, openrouter) and TEXTPOLISH_LIVE_MODEL.
/// Model output varies between runs, so read the printed outputs when a check fails.
@MainActor
final class LivePromptChecks: XCTestCase {
  private struct Checker: TextProcessor {
    let minSimilarity = 0.65
  }

  private let checker = Checker()
  private var corrector: GrammarCorrector?

  private let choppy = """
    Hi team,

    I've updated the report.
    The numbers on page 3 now match the sheet.
    Let me know if anything else is needed.
    """

  override func setUp() async throws {
    try await super.setUp()
    let environment = ProcessInfo.processInfo.environment
    guard environment["TEXTPOLISH_LIVE_CHECKS"] == "1" else {
      throw XCTSkip("Set TEXTPOLISH_LIVE_CHECKS=1 and a provider API key to run live prompt checks.")
    }
    corrector = try Self.makeCorrector(environment: environment)
  }

  // MARK: - Natural

  func testNaturalJoinsChoppyLinesWithoutRewording() async throws {
    let output = try await polish(choppy, style: .clarify)

    XCTAssertTrue(output.hasPrefix("Hi team,\n\n"), "The greeting and the blank line after it stay")
    XCTAssertEqual(newlines(in: output), 2, "Lines inside the paragraph are joined")
    XCTAssertGreaterThanOrEqual(
      checker.similarity(flattened(choppy), flattened(output)),
      0.95,
      "The wording was already fine, so only the line breaks should change"
    )
  }

  func testNaturalRewordsAwkwardPhrasing() async throws {
    let input = "pls refer to this, I compiled everything and added status progress, so it can be easier to track, "
      + "also I handled some cases that I could handle, the rest should be you"
    let output = try await polish(input, style: .clarify)

    XCTAssertTrue(output.lowercased().contains("pls"), "Slang stays")
    XCTAssertEqual(newlines(in: output), 0)
    XCTAssertLessThan(checker.similarity(input, output), 0.9, "Awkward phrases are reworded, not only re-punctuated")
  }

  func testNaturalKeepsListItems() async throws {
    let input = "Today I already finish:\n- fix the login bug\n- update the docs\nPlease check it before merge"
    let output = try await polish(input, style: .clarify)

    let items = output.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
    XCTAssertEqual(items.count, 2, "Each bullet stays on its own line")
  }

  func testNaturalKeepsCodeAndLinks() async throws {
    let input = "Please run `swift test` before merge, the details is in https://github.com/kxxil01/TextPolish"
    let output = try await polish(input, style: .clarify)

    XCTAssertTrue(output.contains("`swift test`"))
    XCTAssertTrue(output.contains("https://github.com/kxxil01/TextPolish"))
  }

  func testNaturalKeepsFacts() async throws {
    let input = "pls transfer 2.500.000 rupiah to Budi before Friday 3pm, and tell Sarah the meeting is moved to 14 March"
    let output = try await polish(input, style: .clarify)

    let compact = output.lowercased().replacingOccurrences(of: " ", with: "")
    for fact in ["2.500.000", "budi", "friday", "3pm", "sarah", "14march"] {
      XCTAssertTrue(compact.contains(fact), "Kept \(fact)")
    }
  }

  func testNaturalKeepsIndonesianWords() async throws {
    let input = "tolong cek ya, I already update the file but the number still not match"
    let output = try await polish(input, style: .clarify)

    XCTAssertTrue(output.lowercased().contains("tolong"), "Words in another language are not translated")
  }

  func testNaturalLeavesNaturalTextAlone() async throws {
    let input = "Thanks for the update. I'll review it today and get back to you."
    let output = try await polish(input, style: .clarify)

    XCTAssertEqual(output, input)
  }

  // MARK: - Minimal

  func testMinimalFixesTyposAndKeepsSlang() async throws {
    let input = "i dont think thats gonna work tbh, lets try tomorow"
    let output = try await polish(input, style: .minimal)

    XCTAssertTrue(output.contains("tomorrow"))
    XCTAssertTrue(output.contains("tbh"))
    XCTAssertTrue(output.contains("gonna"))
  }

  func testMinimalKeepsEveryLine() async throws {
    let output = try await polish(choppy, style: .minimal)

    XCTAssertEqual(newlines(in: output), newlines(in: choppy))
  }

  func testMinimalLeavesCorrectTextAlone() async throws {
    let input = "Thanks for the update. I'll review it today."
    let output = try await polish(input, style: .minimal)

    XCTAssertEqual(output, input)
  }

  // MARK: - Helpers

  private func polish(_ input: String, style: CorrectionStyle) async throws -> String {
    let corrector = try XCTUnwrap(corrector)
    let started = Date()
    let output = try await corrector.correct(input, style: style)
    let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
    print("[LivePromptChecks] \(name) \(style) \(seconds)s\n  in:  \(input.debugDescription)\n  out: \(output.debugDescription)")
    return output
  }

  private func newlines(in text: String) -> Int {
    text.filter(\.isNewline).count
  }

  private func flattened(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func makeCorrector(environment: [String: String]) throws -> GrammarCorrector {
    let provider = (environment["TEXTPOLISH_LIVE_PROVIDER"] ?? "openai").lowercased()
    let model = environment["TEXTPOLISH_LIVE_MODEL"]
    var settings = Settings(requestTimeoutSeconds: 60)
    switch provider {
    case "openai":
      settings.provider = .openAI
      settings.openAIApiKey = try requiredKey("OPENAI_API_KEY", in: environment)
      settings.openAIModel = model ?? settings.openAIModel
    case "gemini":
      settings.provider = .gemini
      settings.geminiApiKey = try requiredKey("GEMINI_API_KEY", in: environment)
      settings.geminiModel = model ?? settings.geminiModel
    case "anthropic":
      settings.provider = .anthropic
      settings.anthropicApiKey = try requiredKey("ANTHROPIC_API_KEY", in: environment)
      settings.anthropicModel = model ?? settings.anthropicModel
    case "openrouter":
      settings.provider = .openRouter
      settings.openRouterApiKey = try requiredKey("OPENROUTER_API_KEY", in: environment)
      settings.openRouterModel = model ?? settings.openRouterModel
    default:
      throw XCTSkip("Unknown TEXTPOLISH_LIVE_PROVIDER \"\(provider)\"; use openai, gemini, anthropic or openrouter.")
    }
    return CorrectorFactory.make(settings: settings)
  }

  private static func requiredKey(_ name: String, in environment: [String: String]) throws -> String {
    let key = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !key.isEmpty else {
      throw XCTSkip("Set \(name) to run live prompt checks against this provider.")
    }
    return key
  }
}
