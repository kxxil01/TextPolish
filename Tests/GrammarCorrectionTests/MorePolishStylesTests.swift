import XCTest

@testable import GrammarCorrection

/// Shorter, Formal, and Friendly rewrite wording like Natural, each toward its own goal.
final class MorePolishStylesTests: XCTestCase {
  private let rewriteStyles: [CorrectionStyle] = [.shorten, .formal, .friendly]

  private func prompt(_ style: CorrectionStyle, retryReason: CorrectionRetryReason? = nil) -> String {
    CorrectionPromptBuilder.makePrompt(
      text: "hello", retryReason: retryReason, correctionLanguage: .auto, extraInstruction: nil, style: style
    ).system
  }

  func testEachStyleAsksForItsOwnGoalWithExamples() {
    XCTAssertTrue(prompt(.shorten).contains("Make the text shorter"))
    XCTAssertTrue(prompt(.formal).contains("polite, professional tone"))
    XCTAssertTrue(prompt(.friendly).contains("warm, friendly, casual tone"))
    for style in rewriteStyles {
      XCTAssertTrue(prompt(style).contains("Example output:"), "\(style) has an example")
      XCTAssertFalse(prompt(style).contains("Improve the text so it reads clearly"), "\(style) does not reuse Natural's goal")
    }
  }

  func testRewriteStylesKeepMeaningAndShareTheLineJoiningRule() {
    for style in rewriteStyles {
      let system = prompt(style)
      XCTAssertTrue(system.contains("Keep the meaning exactly"), "\(style)")
      XCTAssertTrue(system.contains("Do not translate"), "\(style)")
      XCTAssertTrue(system.contains("Join line breaks that split one paragraph"), "\(style)")
      XCTAssertFalse(system.contains("Preserve formatting exactly: whitespace, line breaks"), "\(style)")
    }
  }

  func testRewriteStylesGetRewriteRetryInstructions() {
    for style in rewriteStyles {
      XCTAssertTrue(prompt(style, retryReason: .overRewrite).contains("only rephrase the parts that are unclear"), "\(style)")
      XCTAssertTrue(prompt(style, retryReason: .lineStructureChanged).contains("changed the paragraph layout"), "\(style)")
    }
  }

  func testRewriteStylesAcceptLowerSimilarityAndMayJoinLines() {
    struct Checker: TextProcessor { let minSimilarity = 0.65 }
    let checker = Checker()
    let choppy = "Hi team,\n\nI've updated the report.\nThe numbers now match."
    let joined = "Hi team,\n\nI've updated the report. The numbers now match."

    for style in rewriteStyles {
      XCTAssertEqual(style.minimumSimilarity(configured: 0.65), 0.3, "\(style)")
      XCTAssertTrue(style.rewritesWording)
      XCTAssertTrue(checker.keepsLineStructure(original: choppy, candidate: joined, style: style), "\(style)")
    }
    XCTAssertFalse(CorrectionStyle.minimal.rewritesWording)
  }

  func testRewriteStylesThinkLikeNatural() {
    for style in rewriteStyles {
      XCTAssertEqual(OpenAITokenPolicy.reasoningEffort(model: "gpt-5-nano", style: style), "low", "\(style)")
      XCTAssertEqual(GeminiRequestPolicy.thinkingConfig(model: "gemini-2.5-flash", style: style)?.thinkingBudget, 1024, "\(style)")
    }
  }

  func testSettingsStylesMapToTheirCorrectionStyles() throws {
    XCTAssertEqual(Settings.PolishStyle.shorter.correctionStyle, .shorten)
    XCTAssertEqual(Settings.PolishStyle.formal.correctionStyle, .formal)
    XCTAssertEqual(Settings.PolishStyle.friendly.correctionStyle, .friendly)

    var settings = Settings()
    settings.polishStyle = .formal
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(decoded.polishStyle, .formal)
  }
}
