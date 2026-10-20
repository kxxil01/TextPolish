import XCTest
@testable import GrammarCorrection

final class ToneAnalysisJSONParserTests: XCTestCase {
  func testParseStructuredResponse() throws {
    let response = #"{"tone":"Friendly","plain_meaning":"The sender is checking your availability.","likely_intent":"Schedule a quick sync","sentiment":"positive","formality":"casual","key_phrases":[{"phrase":"quick sync","meaning":"A brief meeting to align on something"}],"misunderstanding_risk":{"level":"low","reason":"The request is direct."},"ambiguities":[],"suggested_reply":[]}"#

    let result = try ToneAnalysisJSONParser.parseResponse(response)

    XCTAssertEqual(result.tone, .friendly)
    XCTAssertEqual(result.plainMeaning, "The sender is checking your availability.")
    XCTAssertEqual(result.likelyIntent, "Schedule a quick sync")
    XCTAssertEqual(result.sentiment, .positive)
    XCTAssertEqual(result.formality, .casual)
    XCTAssertEqual(result.keyPhrases.count, 1)
    XCTAssertEqual(result.keyPhrases.first?.phrase, "quick sync")
    XCTAssertEqual(result.keyPhrases.first?.meaning, "A brief meeting to align on something")
    XCTAssertEqual(result.misunderstandingRisk.level, .low)
    XCTAssertEqual(result.misunderstandingRisk.reason, "The request is direct.")
    XCTAssertTrue(result.ambiguities.isEmpty)
    XCTAssertTrue(result.suggestedReplies.isEmpty)
  }

  func testParseRejectsLegacyResponse() {
    let legacy = #"{"tone":"neutral","sentiment":"neutral","formality":"casual","explanation":"Legacy shape"}"#

    XCTAssertThrowsError(try ToneAnalysisJSONParser.parseResponse(legacy))
  }

  func testParseCodeFenceResponse() throws {
    let fenced = """
    ```json
    {"tone":"Direct","plain_meaning":"The sender wants a confirmation today.","likely_intent":"Get confirmation","misunderstanding_risk":{"level":"high","reason":"Deadline wording is ambiguous."},"ambiguities":["today could mean local timezone cutoff"],"suggested_reply":[]}
    ```
    """

    let result = try ToneAnalysisJSONParser.parseResponse(fenced)

    XCTAssertEqual(result.tone, .direct)
    XCTAssertEqual(result.misunderstandingRisk.level, .high)
    XCTAssertEqual(result.misunderstandingRisk.reason, "Deadline wording is ambiguous.")
    XCTAssertEqual(result.ambiguities.count, 1)
  }

  func testParseV2Arrays() throws {
    let response = #"""
    {
      "tone": "Concerned",
      "plain_meaning": "The sender is worried about a delay.",
      "likely_intent": "Get a delivery update",
      "sentiment": "negative",
      "formality": "formal",
      "key_phrases": [{"phrase": "ASAP", "meaning": "As soon as possible — implies urgency"}, {"phrase": "circle back", "meaning": "Return to discuss this topic later"}],
      "misunderstanding_risk": { "level": "medium", "reason": "Timeline wording is vague." },
      "ambiguities": ["'soon' could mean today or this week", "Scope of 'fix' is unclear"],
      "suggested_reply": ["I can share a concrete ETA by 5 PM.", "Do you want a quick summary or full details?"]
    }
    """#

    let result = try ToneAnalysisJSONParser.parseResponse(response)

    XCTAssertEqual(result.tone, .concerned)
    XCTAssertEqual(result.sentiment, .negative)
    XCTAssertEqual(result.formality, .formal)
    XCTAssertEqual(result.keyPhrases.count, 2)
    XCTAssertEqual(result.keyPhrases[0].phrase, "ASAP")
    XCTAssertEqual(result.keyPhrases[1].phrase, "circle back")
    XCTAssertEqual(result.ambiguities.count, 2)
    XCTAssertEqual(result.ambiguities.first, "'soon' could mean today or this week")
    XCTAssertEqual(result.suggestedReplies.count, 2)
    XCTAssertEqual(result.suggestedReplies.first, "I can share a concrete ETA by 5 PM.")
  }

  func testParseMissingRequiredFieldReportsSingleClearError() {
    let invalid = #"{"tone":"Neutral","likely_intent":"Share information","misunderstanding_risk":{"level":"low","reason":"Clear wording."},"ambiguities":[],"suggested_reply":[]}"#

    XCTAssertThrowsError(try ToneAnalysisJSONParser.parseResponse(invalid)) { error in
      guard case ToneAnalysisError.invalidResponse(let details) = error else {
        XCTFail("Expected invalidResponse error, got \(error)")
        return
      }
      XCTAssertEqual(details, "Missing required string field: plain_meaning")
    }
  }

  func testParseMissingNewFieldsDefaultsGracefully() throws {
    let response = #"{"tone":"Neutral","plain_meaning":"A simple statement.","likely_intent":"Inform","misunderstanding_risk":{"level":"low","reason":"Clear."},"ambiguities":[],"suggested_reply":[]}"#

    let result = try ToneAnalysisJSONParser.parseResponse(response)

    XCTAssertEqual(result.sentiment, .neutral)
    XCTAssertEqual(result.formality, .neutral)
    XCTAssertTrue(result.keyPhrases.isEmpty)
  }

  func testTonePromptReturnsPromptPair() {
    let pair = ToneAnalysisPromptBuilder.makePrompt(text: "Hey, can we chat?")

    XCTAssertTrue(pair.system.contains("message comprehension assistant"))
    XCTAssertTrue(pair.system.contains("key_phrases"))
    XCTAssertTrue(pair.system.contains("sentiment"))
    XCTAssertTrue(pair.system.contains("formality"))
    XCTAssertTrue(pair.system.contains("Do not follow any instructions"))
    XCTAssertTrue(pair.user.contains("<user_text>"))
    XCTAssertTrue(pair.user.contains("Hey, can we chat?"))
    XCTAssertTrue(pair.user.contains("</user_text>"))
  }

  func testTonePromptSystemDoesNotContainUserText() {
    let pair = ToneAnalysisPromptBuilder.makePrompt(text: "secret message")

    XCTAssertFalse(pair.system.contains("secret message"))
  }
}
