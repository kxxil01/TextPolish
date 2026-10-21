import XCTest

@testable import GrammarCorrection

/// Usage and cost: token counts from each provider's response, list prices, and the monthly ledger.
final class UsageTests: XCTestCase {
  func testParsesEachProvidersTokenCounts() {
    let openAI = Data(#"{"choices":[],"usage":{"prompt_tokens":120,"completion_tokens":30,"total_tokens":150}}"#.utf8)
    let anthropic = Data(#"{"content":[],"usage":{"input_tokens":90,"output_tokens":20}}"#.utf8)
    let gemini = Data(#"{"candidates":[],"usageMetadata":{"promptTokenCount":80,"candidatesTokenCount":15,"thoughtsTokenCount":5}}"#.utf8)

    XCTAssertEqual(TokenUsage.parse(openAI), TokenUsage(input: 120, output: 30))
    XCTAssertEqual(TokenUsage.parse(anthropic), TokenUsage(input: 90, output: 20))
    XCTAssertEqual(TokenUsage.parse(gemini), TokenUsage(input: 80, output: 20), "Thinking tokens bill as output")
    XCTAssertNil(TokenUsage.parse(Data(#"{"choices":[]}"#.utf8)), "Some compatible servers report no counts")
    XCTAssertNil(TokenUsage.parse(Data("not json".utf8)))
  }

  func testPricesMatchDatedAndOpenRouterNamesAndPreferTheLongestName() {
    XCTAssertEqual(ModelPricing.price(for: "gpt-4.1-mini"), .init(input: 0.40, output: 1.60))
    XCTAssertEqual(ModelPricing.price(for: "gpt-4.1-mini-2025-04-14"), .init(input: 0.40, output: 1.60))
    XCTAssertEqual(ModelPricing.price(for: "openai/gpt-5-mini"), .init(input: 0.25, output: 2.00))
    XCTAssertEqual(ModelPricing.price(for: "gpt-5"), .init(input: 1.25, output: 10.00))
    XCTAssertEqual(ModelPricing.price(for: "gemini-2.5-flash-lite"), .init(input: 0.10, output: 0.40))
    XCTAssertEqual(ModelPricing.price(for: "claude-haiku-4-5-20251001"), .init(input: 1.00, output: 5.00))
    XCTAssertEqual(ModelPricing.price(for: "google/gemma-3n-e4b-it:free"), .init(input: 0, output: 0))
    XCTAssertNil(ModelPricing.price(for: "llama3.2"))
    XCTAssertNil(ModelPricing.price(for: "gpt-4.1-minimal"), "A longer word is not a dated version")

    let cost = try? XCTUnwrap(ModelPricing.cost(model: "gpt-4.1-mini", inputTokens: 1_000_000, outputTokens: 500_000))
    XCTAssertEqual(cost ?? 0, 1.20, accuracy: 0.0001)
  }

  func testLedgerTotalsEachModelPerMonthAndSurvivesARestart() throws {
    let url = temporaryFile()
    let ledger = UsageLedger(fileURL: url)
    let october = date("2026-10-21")

    ledger.record(provider: .openAI, model: "gpt-4.1-mini", usage: TokenUsage(input: 1000, output: 200), at: october)
    ledger.record(provider: .openAI, model: "gpt-4.1-mini", usage: TokenUsage(input: 500, output: 100), at: october)
    ledger.record(provider: .custom, model: "llama3.2", usage: nil, at: october)
    ledger.record(provider: .openAI, model: "gpt-4.1-mini", usage: TokenUsage(input: 9, output: 9), at: date("2026-09-30"))

    let reloaded = UsageLedger(fileURL: url).usage(inMonthOf: october)
    XCTAssertEqual(reloaded.count, 2)
    XCTAssertEqual(reloaded.first?.model, "gpt-4.1-mini")
    XCTAssertEqual(reloaded.first?.totals, .init(requests: 2, inputTokens: 1500, outputTokens: 300))
    XCTAssertEqual(reloaded.last?.provider, .custom)
    XCTAssertNil(reloaded.last?.estimatedCost)
  }

  func testSummaryShowsTotalsCostAndUnpricedModels() {
    let ledger = UsageLedger(fileURL: temporaryFile())
    let october = date("2026-10-21")
    XCTAssertEqual(ledger.summaryLines(inMonthOf: october), ["No requests yet this month."])

    ledger.record(provider: .openAI, model: "gpt-4.1-mini", usage: TokenUsage(input: 1_000_000, output: 500_000), at: october)
    ledger.record(provider: .custom, model: "llama3.2", usage: TokenUsage(input: 10, output: 10), at: october)
    let lines = ledger.summaryLines(inMonthOf: october)

    XCTAssertTrue(lines[0].hasPrefix("2 requests"), lines[0])
    XCTAssertTrue(lines[0].hasSuffix("about $1.20 for priced models"), lines[0])
    XCTAssertTrue(lines.contains("• OpenAI gpt-4.1-mini: 1 requests, about $1.20"), "\(lines)")
    XCTAssertTrue(lines.contains("• Custom llama3.2: 1 requests, price not known"), "\(lines)")
    XCTAssertTrue(lines.last?.contains("list prices") == true)
  }

  func testLedgerKeepsTwelveMonths() {
    let ledger = UsageLedger(fileURL: temporaryFile())
    for month in 1...14 {
      ledger.record(provider: .gemini, model: "gemini-2.5-flash", usage: nil, at: date(String(format: "2025-%02d-15", min(month, 12)) ))
    }
    for month in 1...3 {
      ledger.record(provider: .gemini, model: "gemini-2.5-flash", usage: nil, at: date(String(format: "2026-%02d-15", month)))
    }

    XCTAssertTrue(ledger.usage(inMonthOf: date("2025-03-15")).isEmpty, "The oldest months are dropped")
    XCTAssertFalse(ledger.usage(inMonthOf: date("2025-04-15")).isEmpty)
    XCTAssertFalse(ledger.usage(inMonthOf: date("2026-03-15")).isEmpty)
  }

  private func temporaryFile() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func date(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: value)!.addingTimeInterval(12 * 3600)
  }
}

extension CorrectorRetryAndPlaceholderTests {
  func testSuccessfulRequestsAreRecordedInTheUsageLedger() async throws {
    MockURLProtocol.handler = { request in
      Self.httpResponse(
        for: request,
        statusCode: 200,
        body: #"{"choices":[{"message":{"content":"hello"}}],"usage":{"prompt_tokens":40,"completion_tokens":2}}"#
      )
    }
    let model = "usage-test-\(UUID().uuidString)"
    var settings = Settings(requestTimeoutSeconds: 1, openAIApiKey: "test-key", openAIBaseURL: "https://mock.local", openAIMaxAttempts: 1)
    settings.openAIModel = model
    let corrector = try OpenAICorrector(settings: settings, session: Self.makeMockSession())

    _ = try await corrector.correct("helo")

    let recorded = UsageLedger.shared.usage().first { $0.model == model }
    XCTAssertEqual(recorded?.provider, .openAI)
    XCTAssertEqual(recorded?.totals, .init(requests: 1, inputTokens: 40, outputTokens: 2))
  }
}
