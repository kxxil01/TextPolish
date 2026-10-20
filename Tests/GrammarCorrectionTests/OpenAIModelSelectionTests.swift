import XCTest

@testable import GrammarCorrection

final class OpenAIModelSelectionTests: XCTestCase {
  /// Shaped like a real /v1/models response: non-chat "mini" models are listed first.
  private let realisticIDs = [
    "gpt-realtime-2.1-mini",
    "gpt-4o-mini-tts",
    "gpt-4o-mini-transcribe",
    "gpt-4o-mini-search-preview",
    "gpt-audio-mini",
    "gpt-image-1",
    "chatgpt-image-latest",
    "gpt-3.5-turbo-instruct",
    "gpt-5-codex",
    "o1-pro",
    "text-embedding-3-small",
    "gpt-4.1",
    "gpt-5-nano-2025-08-07",
    "gpt-5-nano",
    "gpt-5-mini",
  ]

  func testPrefersGPT5NanoOverNonChatMiniModels() {
    XCTAssertEqual(ModelDetector.preferredOpenAIModel(from: realisticIDs), "gpt-5-nano")
  }

  func testFallsBackThroughPreferredChatModels() {
    let withoutNano = realisticIDs.filter { !$0.hasPrefix("gpt-5-nano") }
    XCTAssertEqual(ModelDetector.preferredOpenAIModel(from: withoutNano), "gpt-5-mini")

    let onlyOlderChat = ["gpt-realtime-2.1-mini", "gpt-4.1", "gpt-4o-mini-tts"]
    XCTAssertEqual(ModelDetector.preferredOpenAIModel(from: onlyOlderChat), "gpt-4.1")
  }

  func testReturnsNilWhenOpenAIListHasNoChatModel() {
    let nonChatOnly = ["gpt-realtime-2.1-mini", "gpt-4o-mini-tts", "gpt-image-1", "text-embedding-3-small"]
    XCTAssertNil(ModelDetector.preferredOpenAIModel(from: nonChatOnly))
  }

  func testCompatibleServerWithOwnModelNamesGetsFirstModel() {
    XCTAssertEqual(ModelDetector.preferredOpenAIModel(from: ["qwen2.5:7b", "llama3.1:8b"]), "llama3.1:8b")
  }

  func testSavedNonChatOpenAIModelIsRepairedOnLoad() throws {
    let json = Data(#"{"provider":"openAI","openAIModel":"gpt-realtime-2.1-mini"}"#.utf8)

    let settings = try JSONDecoder().decode(Settings.self, from: json)

    XCTAssertEqual(settings.openAIModel, Settings().openAIModel)
  }

  func testSavedCompatibleServerModelIsKept() throws {
    let json = Data(#"{"provider":"openAI","openAIModel":"llama3.1:8b"}"#.utf8)

    let settings = try JSONDecoder().decode(Settings.self, from: json)

    XCTAssertEqual(settings.openAIModel, "llama3.1:8b")
  }

  func testChatModelClassification() {
    for id in ["gpt-5-nano", "gpt-4.1-mini", "gpt-4o", "gpt-3.5-turbo", "o3-mini", "o4-mini", "gpt-5-chat-latest"] {
      XCTAssertTrue(OpenAITokenPolicy.isChatModel(id), "\(id) should be a chat model")
    }
    for id in [
      "gpt-realtime-2.1-mini", "gpt-4o-mini-tts", "gpt-4o-mini-transcribe", "gpt-audio-mini",
      "gpt-image-1", "chatgpt-image-latest", "gpt-3.5-turbo-instruct", "gpt-4o-mini-search-preview",
      "gpt-5-codex", "o1-pro", "gpt-5-pro-2025-10-06", "o3-deep-research", "text-embedding-3-small",
    ] {
      XCTAssertFalse(OpenAITokenPolicy.isChatModel(id), "\(id) should not be a chat model")
    }
  }
}
