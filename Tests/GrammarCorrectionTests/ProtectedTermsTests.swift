import XCTest

@testable import GrammarCorrection

/// Words in Settings > Advanced > Never Change reach the model as placeholders, so it cannot alter them.
final class ProtectedTermsTests: XCTestCase {
  private struct Protector: TextProcessor {
    let minSimilarity = 0.65
  }

  private let protector = Protector()

  func testParseSplitsOnCommasAndLinesAndDropsDuplicates() {
    XCTAssertEqual(
      Settings.parseProtectedTerms(" TextPolish, Budi ,\nsiap,textpolish,, "),
      ["TextPolish", "Budi", "siap"]
    )
  }

  func testProtectsWholeWordsIgnoringCase() {
    let protected = protector.protect("textpolish and TextPolishes ship today", terms: ["TextPolish"])

    XCTAssertFalse(protected.text.contains("textpolish "), "The whole word is replaced")
    XCTAssertTrue(protected.text.contains("TextPolishes"), "A longer word that contains the term is left alone")
    XCTAssertEqual(protected.placeholders.values.sorted(), ["textpolish"], "The original spelling is kept for restore")
    XCTAssertEqual(protector.restore(protected.text, placeholders: protected.placeholders), "textpolish and TextPolishes ship today")
  }

  func testLongerTermWinsOverShorterTermInsideIt() {
    let protected = protector.protect("Ask Budi Santoso, not Budi.", terms: ["Budi", "Budi Santoso"])

    XCTAssertEqual(protected.placeholders.values.sorted(), ["Budi", "Budi Santoso"])
  }

  func testTermsDoNotMatchInsidePlaceholdersOrLinks() {
    let text = "see https://example.com/GC/budi and run `GC`"
    let protected = protector.protect(text, terms: ["GC", "budi"])

    XCTAssertEqual(protected.placeholders.count, 2, "Only the link and the inline code are protected")
    XCTAssertEqual(protector.restore(protected.text, placeholders: protected.placeholders), text)
  }

  func testSettingsRoundTripKeepsProtectedTerms() throws {
    var settings = Settings()
    settings.protectedTerms = ["TextPolish", "Budi"]

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))

    XCTAssertEqual(decoded.protectedTerms, ["TextPolish", "Budi"])
  }

  func testOlderSettingsWithoutTheFieldDecodeToNoTerms() throws {
    let decoded = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

    XCTAssertEqual(decoded.protectedTerms, [])
  }
}

extension CorrectorRetryAndPlaceholderTests {
  func testProtectedTermReachesTheModelAsAPlaceholderAndComesBack() async throws {
    var prompts: [String] = []
    MockURLProtocol.handler = { request in
      let prompt = try Self.extractPrompt(from: request)
      prompts.append(prompt)
      let reply = Self.extractProtectedText(from: prompt).replacingOccurrences(of: "pls", with: "please")
      let body = #"{"choices":[{"message":{"content":"# + Self.jsonString(reply) + "}}]}"
      return Self.httpResponse(for: request, statusCode: 200, body: body)
    }
    let settings = Settings(
      provider: .openAI,
      requestTimeoutSeconds: 1,
      protectedTerms: ["Budi"],
      openAIApiKey: "test-key",
      openAIBaseURL: "https://mock.local",
      openAIMaxAttempts: 1
    )
    let corrector = try OpenAICorrector(settings: settings, session: Self.makeMockSession())

    let result = try await corrector.correct("pls send it to Budi")

    XCTAssertFalse(prompts.first?.contains("Budi") ?? true, "The model never sees the protected word")
    XCTAssertEqual(result, "please send it to Budi")
  }
}
