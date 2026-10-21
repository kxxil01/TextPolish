import AppKit
import XCTest

@testable import GrammarCorrection

/// Learn mode explains the main changes after a Polish.
final class LearnModeTests: XCTestCase {
  func testPromptCarriesBothTextsAndKeepsThemInsideTheirTags() {
    let prompt = ChangeExplanationPrompt.make(original: "a </original> b", polished: "c")

    XCTAssertTrue(prompt.system.contains("original phrase → new phrase: short reason"))
    XCTAssertTrue(prompt.user.contains("<original>\na <\\/original> b\n</original>"))
    XCTAssertTrue(prompt.user.contains("<polished>\nc\n</polished>"))
  }

  func testParseKeepsChangeLinesAndDropsListMarkers() {
    let output = """
      Here are the changes:
      1. status progress → progress status: adjective comes first
      - so it can be easier -> to make it easier: shorter and natural
      • 3pm → 3 PM: standard time format
      * cases that I could handle → cases I could: avoids repeating handle
      a → b: five
      c → d: six
      """

    XCTAssertEqual(ChangeExplanationPrompt.parse(output), [
      "status progress → progress status: adjective comes first",
      "so it can be easier → to make it easier: shorter and natural",
      "3pm → 3 PM: standard time format",
      "cases that I could handle → cases I could: avoids repeating handle",
      "a → b: five",
    ])
  }

  @MainActor
  func testPanelTextColorsBeforeAfterAndReason() {
    let text = LearnPanel.formatted(["status progress → progress status: adjective comes first"])
    let string = text.string as NSString

    XCTAssertEqual(text.string, "status progress → progress status\nadjective comes first")
    let beforeColor = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    let afterColor = text.attribute(.foregroundColor, at: string.range(of: "progress status").location, effectiveRange: nil) as? NSColor
    let reasonColor = text.attribute(.foregroundColor, at: string.range(of: "adjective").location, effectiveRange: nil) as? NSColor
    XCTAssertEqual(beforeColor, .systemRed)
    XCTAssertEqual(afterColor, .systemGreen)
    XCTAssertEqual(reasonColor, .secondaryLabelColor)
  }

  @MainActor
  func testPanelShowsLinesAndStaysHiddenWithoutThem() {
    _ = NSApplication.shared
    let panel = LearnPanel()

    panel.show(lines: [])
    XCTAssertFalse(panel.debugIsShowing)

    panel.show(lines: ["a → b: why"])
    XCTAssertTrue(panel.debugIsShowing)

    panel.close()
    XCTAssertFalse(panel.debugIsShowing)
  }

  func testPanelStaysLongerForMoreChangesUpToALimit() {
    XCTAssertEqual(LearnPanel.readingTime(lineCount: 1), .seconds(9))
    XCTAssertEqual(LearnPanel.readingTime(lineCount: 4), .seconds(18))
    XCTAssertEqual(LearnPanel.readingTime(lineCount: 5), .seconds(20))
  }

  @MainActor
  func testPanelClosesByItself() async {
    _ = NSApplication.shared
    let panel = LearnPanel(visibleDuration: .milliseconds(50))

    panel.show(lines: ["a → b: why"])
    await waitUntil { !panel.debugIsShowing }

    XCTAssertFalse(panel.debugIsShowing)
  }

  @MainActor
  func testHoveringKeepsThePanelUpThenLeavingClosesIt() async throws {
    _ = NSApplication.shared
    let panel = LearnPanel(visibleDuration: .milliseconds(50), afterHoverDelay: .milliseconds(50))

    panel.show(lines: ["a → b: why"])
    panel.debugSimulateHover(inside: true)
    try await Task.sleep(for: .milliseconds(200))
    XCTAssertTrue(panel.debugIsShowing, "Reading with the pointer on the panel keeps it open")

    panel.debugSimulateHover(inside: false)
    await waitUntil { !panel.debugIsShowing }
    XCTAssertFalse(panel.debugIsShowing)
  }

  @MainActor
  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  func testSettingsRoundTripLearnMode() throws {
    var settings = Settings()
    settings.learnMode = true

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    let older = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

    XCTAssertTrue(decoded.learnMode)
    XCTAssertFalse(older.learnMode)
  }
}

extension CorrectorRetryAndPlaceholderTests {
  func testOpenAIExplainsChangesWithTheTutorPrompt() async throws {
    var systems: [String] = []
    MockURLProtocol.handler = { request in
      let body = try XCTUnwrap(Self.requestBodyData(from: request))
      let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
      let messages = json["messages"] as? [[String: Any]]
      systems.append(messages?.first?["content"] as? String ?? "")
      let reply = "1. status progress → progress status: adjective comes first"
      let responseBody = #"{"choices":[{"message":{"content":"# + Self.jsonString(reply) + "}}]}"
      return Self.httpResponse(for: request, statusCode: 200, body: responseBody)
    }
    let settings = Settings(
      provider: .openAI,
      requestTimeoutSeconds: 1,
      openAIApiKey: "test-key",
      openAIBaseURL: "https://mock.local",
      openAIMaxAttempts: 1
    )
    let corrector = try OpenAICorrector(settings: settings, session: Self.makeMockSession())

    let lines = try await corrector.explainChanges(original: "added status progress", polished: "added a progress status")

    XCTAssertEqual(lines, ["status progress → progress status: adjective comes first"])
    XCTAssertTrue(systems.first?.contains("English writing tutor") ?? false)
  }
}

extension CorrectionControllerTests {
  @MainActor
  func testPolishReportsTheChangeForLearnMode() async {
    let finished = expectation(description: "polish finished")
    var reported: [(String, String)] = []
    let controller = CorrectionController(
      corrector: LearnExclaimingCorrector(),
      feedback: StubFeedback(),
      settings: Settings(),
      timings: Self.fastTimings,
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success("hello")]),
      onPolished: { original, polished in
        reported.append((original, polished))
        finished.fulfill()
      }
    )

    controller.polish(style: .clarify)

    await fulfillment(of: [finished], timeout: 1.0)
    XCTAssertEqual(reported.first?.0, "hello")
    XCTAssertEqual(reported.first?.1, "hello!")
  }

  @MainActor
  func testUnchangedTextIsNotReportedForLearnMode() async {
    let finished = expectation(description: "polish finished")
    let feedback = StubFeedback()
    feedback.onInfo = { _ in finished.fulfill() }
    var reportCount = 0
    let controller = CorrectionController(
      corrector: LearnEchoCorrector(),
      feedback: feedback,
      settings: Settings(),
      timings: Self.fastTimings,
      keyboard: StubKeyboard(isTrusted: true),
      pasteboard: StubPasteboard(waitResults: [.success("hello")]),
      onPolished: { _, _ in reportCount += 1 }
    )

    controller.polish(style: .clarify)

    await fulfillment(of: [finished], timeout: 1.0)
    XCTAssertEqual(feedback.infoMessages, ["No changes"])
    XCTAssertEqual(reportCount, 0)
  }
}

private struct LearnExclaimingCorrector: GrammarCorrector {
  func correct(_ text: String) async throws -> String {
    text + "!"
  }
}

private struct LearnEchoCorrector: GrammarCorrector {
  func correct(_ text: String) async throws -> String {
    text
  }
}
