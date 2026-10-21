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
      .numbersChanged
    )
  }

  func testRewordingAroundTheSameNumbersIsAccepted() {
    let reworded = "pls transfer 2.500.000 rupiah to Budi before Friday 3pm, and tell Sarah the meeting has moved to 14 March."

    XCTAssertTrue(checker.keepsNumbers(original: original, candidate: reworded))
    XCTAssertNil(checker.rejectionReason(original: original, candidate: reworded, style: .clarify, minimumSimilarity: 0.4))
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
  }
}
