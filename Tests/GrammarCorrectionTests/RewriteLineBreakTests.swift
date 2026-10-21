import XCTest

@testable import GrammarCorrection

/// Rewrite may join lines inside a paragraph; it must keep paragraphs and lists and never add lines.
final class RewriteLineBreakTests: XCTestCase {
  private struct LineChecker: TextProcessor {
    let minSimilarity = 0.65
  }

  private let checker = LineChecker()
  private let choppy = """
    Hi team,

    I've updated the report.
    The numbers on page 3 now match the sheet.
    Let me know if anything else is needed.
    """
  private let joined = """
    Hi team,

    I've updated the report, and the numbers on page 3 now match the sheet. Let me know if anything else is needed.
    """

  func testRejectionSummaryReportsCountsAndScoreWithoutText() {
    let summary = checker.rejectionSummary(original: choppy, candidate: joined, minimumSimilarity: 0.4)

    XCTAssertTrue(summary.hasPrefix("lines 4->2 blank 1->1 list 0->0 similarity 0."), summary)
    XCTAssertTrue(summary.hasSuffix("(min 0.40)"), summary)
    XCTAssertFalse(summary.contains("report"), "The log line must never include the user's text")
  }

  func testCleanupDropsTrailingSpacesTheModelAdded() {
    let added = "Hi team,\n\nI've updated the report.  \nThe numbers now match.  \nThanks"
    let original = "Hi team,\n\nI've updated the report.\nThe numbers now match.\nThanks"

    XCTAssertEqual(checker.cleanup(added, original: original), original)
    XCTAssertEqual(
      checker.cleanup("a  \nb", original: "a  \nb"),
      "a  \nb",
      "Spaces the writer typed before a line break stay"
    )
  }

  func testCorrectKeepsEveryLine() {
    XCTAssertTrue(checker.keepsLineStructure(original: choppy, candidate: choppy, style: .minimal))
    XCTAssertFalse(checker.keepsLineStructure(original: choppy, candidate: joined, style: .minimal))
  }

  func testRewriteMayJoinLinesInsideAParagraph() {
    XCTAssertTrue(checker.keepsLineStructure(original: choppy, candidate: joined, style: .clarify))
  }

  func testRewriteNeverAddsLines() {
    let added = "one sentence.\nanother sentence."
    XCTAssertFalse(checker.keepsLineStructure(original: "one sentence. another sentence.", candidate: added, style: .clarify))
  }

  func testRewriteKeepsParagraphBreaks() {
    let merged = "Hi team, I've updated the report, and the numbers now match."
    XCTAssertFalse(checker.keepsLineStructure(original: choppy, candidate: merged, style: .clarify))
  }

  func testRewriteKeepsListItems() {
    let list = "Done today:\n- fixed login\n- updated docs\n1. ship it"
    let flattened = "Done today: fixed login, updated docs, and ship it."
    XCTAssertFalse(checker.keepsLineStructure(original: list, candidate: flattened, style: .clarify))

    let reworded = "Done today:\n- fixed the login\n- updated the docs\n1. ship it"
    XCTAssertTrue(checker.keepsLineStructure(original: list, candidate: reworded, style: .clarify))
  }

  func testPromptLineBreakRulesDifferByStyle() {
    let minimal = CorrectionPromptBuilder.makePrompt(
      text: "hello", retryReason: nil, correctionLanguage: .auto, extraInstruction: nil, style: .minimal
    )
    let clarify = CorrectionPromptBuilder.makePrompt(
      text: "hello", retryReason: nil, correctionLanguage: .auto, extraInstruction: nil, style: .clarify
    )

    XCTAssertTrue(minimal.system.contains("Preserve formatting exactly: whitespace, line breaks"))
    XCTAssertFalse(minimal.system.contains("Join line breaks"))
    XCTAssertTrue(clarify.system.contains("Join line breaks that split one paragraph"))
    XCTAssertTrue(clarify.system.contains("never add new line breaks"))
    XCTAssertFalse(clarify.system.contains("whitespace, line breaks"))
    // Text with nothing to reword must still get its lines joined.
    XCTAssertFalse(clarify.system.contains("return it unchanged"))
    XCTAssertTrue(clarify.system.contains("keep the words unchanged, but still join lines that split a paragraph"))
    XCTAssertTrue(clarify.system.contains(
      "Example output: Hi Sam,\n\nThe build is done. I uploaded it to the shared folder. Tell me if you need anything else."
    ))
  }
}

extension CorrectorRetryAndPlaceholderTests {
  func testClarifyAcceptsJoinedParagraphThatCorrectRejects() async throws {
    let choppy = "I've updated the report.\nThe numbers on page 3 now match the sheet."
    let joined = "I've updated the report, and the numbers on page 3 now match the sheet."
    MockURLProtocol.handler = { request in
      let body = #"{"choices":[{"message":{"content":"# + Self.jsonString(joined) + "}}]}"
      return Self.httpResponse(for: request, statusCode: 200, body: body)
    }
    let settings = Settings(
      provider: .openAI,
      requestTimeoutSeconds: 1,
      openAIApiKey: "test-key",
      openAIBaseURL: "https://mock.local",
      openAIMaxAttempts: 1
    )
    let corrector = try OpenAICorrector(settings: settings, session: Self.makeMockSession())

    let rewritten = try await corrector.correct(choppy, style: .clarify)
    XCTAssertEqual(rewritten, joined)

    do {
      _ = try await corrector.correct(choppy)
      XCTFail("Correct must keep every line")
    } catch {}
  }
}
