import XCTest

@testable import GrammarCorrection

/// Sends real Polish prompts to a real provider so prompt regressions show up before a release.
/// Skipped unless TEXTPOLISH_LIVE_CHECKS=1, so CI never calls a provider. A run costs a few cents.
///
///     TEXTPOLISH_LIVE_CHECKS=1 OPENAI_API_KEY=sk-... swift test --filter LivePromptChecks
///
/// Optional: TEXTPOLISH_LIVE_PROVIDER (openai, gemini, anthropic, openrouter, custom) and TEXTPOLISH_LIVE_MODEL.
/// Custom needs TEXTPOLISH_LIVE_BASE_URL and TEXTPOLISH_LIVE_MODEL; TEXTPOLISH_CUSTOM_API_KEY is optional.
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
    XCTAssertFalse(output.contains(" \n"), "No trailing spaces added before line breaks")
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

  /// 0.0.79 could not polish this: the model wrote "one more week" and the number check rejected every attempt.
  func testNaturalPolishesChatWithASmallNumber() async throws {
    let input = "Gonna extend 1 week more of silence"
    let output = try await polish(input, style: .clarify)

    XCTAssertTrue(output.contains("1") || output.lowercased().contains("one"), "Kept the number")
    XCTAssertTrue(output.lowercased().contains("week"))
  }

  func testNaturalKeepsChatAbbreviations() async throws {
    let input = "so please keep future queries to short time ranges with tight filters, ty"
    let output = try await polish(input, style: .clarify)

    let words = output.lowercased().split(whereSeparator: { !$0.isLetter })
    XCTAssertTrue(words.contains("ty"), "Chat abbreviations stay in Natural")
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

  // MARK: - Shorter, Formal, Friendly

  func testShorterCutsFillerAndKeepsFacts() async throws {
    let input = "hi, just wanted to let you know that I have already finished the monthly report for March "
      + "and I have also already uploaded it to the shared folder, so whenever you have some free time you can check it, "
      + "thank you so much"
    let output = try await polish(input, style: .shorten)

    XCTAssertLessThan(Double(output.count), Double(input.count) * 0.8, "At least a fifth shorter")
    XCTAssertTrue(output.lowercased().contains("march"))
    XCTAssertTrue(output.lowercased().contains("shared folder"))
  }

  func testFormalSpellsOutChatAbbreviations() async throws {
    let input = "thx for the update, pls check the numbers again and lmk if anything looks off"
    let output = try await polish(input, style: .formal)

    for slang in ["thx", "pls", "lmk"] {
      XCTAssertFalse(output.lowercased().split(whereSeparator: { !$0.isLetter }).contains(Substring(slang)), "Spelled out \(slang)")
    }
    XCTAssertTrue(output.lowercased().contains("please"))
  }

  func testFriendlySoftensWithoutChangingTheAsk() async throws {
    let input = "Send the files today. Do not forget the contract."
    let output = try await polish(input, style: .friendly)

    XCTAssertNotEqual(output, input)
    XCTAssertFalse(output.contains("’"), "Straight apostrophes in, straight apostrophes out")
    for word in ["files", "today", "contract"] {
      XCTAssertTrue(output.lowercased().contains(word), "Kept \(word)")
    }
  }

  // MARK: - Learn mode

  func testCustomStyleFollowsTheWritersInstruction() async throws {
    let input = "I finished the report and also the deck, and I sent both of them to Sam on 14 March."
    let output = try await polish(input, style: .custom("A short status update as bullet points, one per task"))

    XCTAssertTrue(output.contains("- ") || output.contains("• "), "Bullet points as asked")
    for word in ["report", "deck", "Sam", "14 March"] {
      XCTAssertTrue(output.contains(word), "Kept \(word)")
    }
  }

  func testTranslateWritesNaturalEnglishAndKeepsFacts() async throws {
    let input = "tolong cek laporan yang gw kirim kemarin ya, totalnya Rp 2.500.000 dan deadline 14 Maret"
    let output = try await polish(input, style: .translateToEnglish)

    for word in ["report", "Rp 2.500.000", "14"] {
      XCTAssertTrue(output.contains(word), "Has \(word)")
    }
    for word in ["tolong", "laporan", "kemarin"] {
      XCTAssertFalse(output.lowercased().contains(word), "Translated \(word)")
    }
  }

  func testReplyAnswersInEnglishAndKeepsTheDraftsFacts() async throws {
    let input = "oke nanti gw kirim sebelum jam 3 ya"
    let output = try await polish(input, style: .reply(answering: "Can you send the deck before the 3pm call?"))

    XCTAssertTrue(output.contains("3"), "Kept the time")
    XCTAssertTrue(output.lowercased().contains("send"))
    XCTAssertFalse(output.lowercased().contains("kirim"), "Written in English")
  }

  func testQuickReplyNeverInventsATime() async throws {
    let generator = try XCTUnwrap(corrector as? TextGenerating)
    let message = "Can you send the updated deck today?"
    let reply = ReplySuggestionPrompt.clean(
      try await generator.generateText(ReplySuggestionPrompt.make(message: message, intent: .moreTime))
    )
    print("[LivePromptChecks] quick reply moreTime\n  in:  \(message)\n  out: \(reply)")

    XCTAssertFalse(reply.isEmpty)
    XCTAssertFalse(reply.contains(where: \.isNumber), "No invented times or dates")
  }

  func testExplainGivesTheMeaningInIndonesian() async throws {
    let explainer = try XCTUnwrap(corrector as? MessageExplaining)
    let message = "Can you ping me EOD with a heads-up if the build slips?"
    let explanation = try await explainer.explainMessage(message, in: .indonesian)
    print("[LivePromptChecks] explain\n  in:  \(message)\n  out: \(explanation)")

    XCTAssertFalse(explanation.meaning.isEmpty)
    XCTAssertNotNil(explanation.tone)
    XCTAssertFalse(explanation.meaning.lowercased().contains("can you"), "Written in Indonesian")
  }

  func testLearnExplainsTheMainChanges() async throws {
    let explainer = try XCTUnwrap(corrector as? ChangeExplaining)
    let original = "I compiled everything and added status progress, so it can be easier to track"
    let polished = "I compiled everything and added a progress status to make it easier to track"

    let lines = try await explainer.explainChanges(original: original, polished: polished)
    print("[LivePromptChecks] \(name)\n  " + lines.joined(separator: "\n  "))

    XCTAssertFalse(lines.isEmpty)
    XCTAssertTrue(lines.allSatisfy { $0.contains("→") })
    let befores = lines.compactMap { $0.components(separatedBy: "→").first?.trimmingCharacters(in: .whitespaces).lowercased() }
    for (index, before) in befores.enumerated() {
      let others = befores.enumerated().filter { $0.offset != index }.map(\.element)
      XCTAssertFalse(others.contains { $0.contains(before) }, "\"\(before)\" is listed again inside another change")
      XCTAssertLessThanOrEqual(before.split(separator: " ").count, 8, "\"\(before)\" quotes more than the change")
    }
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
    XCTAssertFalse(output.contains(" \n"), "No trailing spaces added before line breaks")
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
    // Providers check the keychain before the key passed here; clear any test-run keys so the real one is used.
    for account in ["openAIApiKey", "geminiApiKey", "anthropicApiKey", "openRouterApiKey", "customApiKey"] {
      try? Keychain.deleteConfiguredPassword(primaryService: Keychain.testPrimaryService, account: account)
    }
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
    case "custom":
      settings.provider = .custom
      settings.customProvider = Settings.CustomProvider(
        baseURL: try requiredKey("TEXTPOLISH_LIVE_BASE_URL", in: environment),
        model: try requiredKey("TEXTPOLISH_LIVE_MODEL", in: environment),
        apiKey: environment["TEXTPOLISH_CUSTOM_API_KEY"]
      )
    default:
      throw XCTSkip("Unknown TEXTPOLISH_LIVE_PROVIDER \"\(provider)\"; use openai, gemini, anthropic, openrouter or custom.")
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
