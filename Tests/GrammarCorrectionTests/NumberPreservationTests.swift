import XCTest

@testable import GrammarCorrection

/// Polish keeps numbers, amounts, dates, and times in the writer's own format.
final class NumberPreservationTests: XCTestCase {
  private struct Checker: TextProcessor {
    let minSimilarity = 0.65
  }

  private let checker = Checker()
  private let original = "pls transfer 2.500.000 rupiah to Budi before Friday 3pm, and tell Sarah the meeting is moved to 14 March"

  func testNumberTokensKeepTheirSeparators() {
    XCTAssertEqual(
      checker.numberTokens(in: "send 2.500.000 by 3pm, at 07:11 on 14 March."),
      ["2.500.000", "3", "07:11", "14"]
    )
  }

  func testReformattedAmountIsRejected() {
    let reformatted = "pls transfer 2,500,000 rupiah to Budi before Friday 3pm, and tell Sarah the meeting has moved to 14 March."

    XCTAssertFalse(checker.keepsNumbers(original: original, candidate: reformatted))
    XCTAssertEqual(
      checker.rejectionReason(original: original, candidate: reformatted, style: .clarify, minimumSimilarity: 0.4),
      .numbersChanged(["2.500.000"])
    )
  }

  func testRewordingAroundTheSameNumbersIsAccepted() {
    let reworded = "pls transfer 2.500.000 rupiah to Budi before Friday 3pm, and tell Sarah the meeting has moved to 14 March."

    XCTAssertTrue(checker.keepsNumbers(original: original, candidate: reworded))
    XCTAssertNil(checker.rejectionReason(original: original, candidate: reworded, style: .clarify, minimumSimilarity: 0.4))
  }

  /// The message that could not be polished in 0.0.79: every rewrite spelled "1" as "one" and was rejected.
  func testRewritesMaySpellOutASmallNumber() {
    let message = "Gonna extend 1 week more of silence"

    XCTAssertNil(reason(message, "Gonna extend the silence one more week.", .clarify))
    XCTAssertNil(reason("back in 5 min", "Back in five minutes.", .friendly))
    XCTAssertEqual(
      reason(message, "Gonna extend the silence two more weeks.", .clarify), .numbersChanged(["1"]),
      "A different number is still a changed fact"
    )
    XCTAssertEqual(
      reason(message, "Gonna extend one week more of silence", .minimal), .numbersChanged(["1"]),
      "Minimal keeps the digits as written"
    )
    XCTAssertEqual(
      reason("we need 25 seats", "We need twenty-five seats.", .clarify), .numbersChanged(["25"]),
      "Only small numbers may become words"
    )
  }

  private func reason(_ original: String, _ candidate: String, _ style: CorrectionStyle) -> CorrectionRetryReason? {
    checker.rejectionReason(original: original, candidate: candidate, style: style, minimumSimilarity: 0.2)
  }

  func testRetryNamesTheNumbersToKeepWithoutLoggingThem() {
    let reason = CorrectionRetryReason.numbersChanged(["1", "2.500.000"])

    XCTAssertTrue(reason.promptInstruction(for: .clarify).contains("Keep these exactly as written: 1, 2.500.000."))
    XCTAssertEqual("\(reason)", "numbersChanged", "Logs never carry the writer's numbers")
  }

  func testEveryStyleAsksToKeepNumberFormats() {
    for style in [CorrectionStyle.minimal, .clarify, .shorten, .formal, .friendly] {
      let system = CorrectionPromptBuilder.makePrompt(
        text: "hello", retryReason: nil, correctionLanguage: .auto, extraInstruction: nil, style: style
      ).system
      XCTAssertTrue(system.contains("2.500.000 stays 2.500.000"), "\(style)")
    }
  }
}

extension CorrectorRetryAndPlaceholderTests {
  func testChangedNumberFormatRetriesWithTheNumbersInstruction() async throws {
    let input = "pls transfer 2.500.000 rupiah before Friday"
    var systems: [String] = []
    MockURLProtocol.handler = { request in
      let body = try XCTUnwrap(Self.requestBodyData(from: request))
      let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
      let messages = json["messages"] as? [[String: Any]]
      systems.append(messages?.first?["content"] as? String ?? "")
      let reply = systems.count == 1
        ? "pls transfer 2,500,000 rupiah before Friday."
        : "pls transfer 2.500.000 rupiah before Friday."
      let responseBody = #"{"choices":[{"message":{"content":"# + Self.jsonString(reply) + "}}]}"
      return Self.httpResponse(for: request, statusCode: 200, body: responseBody)
    }
    let settings = Settings(
      provider: .openAI,
      requestTimeoutSeconds: 1,
      openAIApiKey: "test-key",
      openAIBaseURL: "https://mock.local",
      openAIMaxAttempts: 2
    )
    let corrector = try OpenAICorrector(settings: settings, session: Self.makeMockSession())

    let result = try await corrector.correct(input, style: .clarify)

    XCTAssertEqual(result, "pls transfer 2.500.000 rupiah before Friday.")
    XCTAssertEqual(systems.count, 2)
    XCTAssertTrue(systems[1].contains("changed a number, amount, date, or time"))
    XCTAssertTrue(systems[1].contains("Keep these exactly as written: 2.500.000."))
  }
}
