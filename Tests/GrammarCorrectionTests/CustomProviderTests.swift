import AppKit
import XCTest

@testable import GrammarCorrection

/// The Custom provider: any OpenAI-compatible API, with an optional key.
final class CustomProviderSettingsTests: XCTestCase {
  func testSettingsRoundTripAndOlderFilesHaveNoCustomProvider() throws {
    var settings = Settings()
    settings.provider = .custom
    settings.customProvider = Settings.CustomProvider(baseURL: "http://localhost:11434/v1", model: "llama3.2", maxAttempts: 3)

    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    let older = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))

    XCTAssertEqual(decoded.provider, .custom)
    XCTAssertEqual(decoded.customProvider, settings.customProvider)
    XCTAssertEqual(older.customProvider, Settings.CustomProvider())
    XCTAssertFalse(older.customProvider.isConfigured)
  }

  func testValuesAreTrimmedClampedAndABadURLReadsAsNotSet() {
    let custom = Settings.CustomProvider(
      baseURL: "  https://api.groq.com/openai/v1 ",
      model: " llama-3.3-70b-versatile ",
      apiKey: "  ",
      maxAttempts: 20,
      minSimilarity: 3,
      extraInstruction: " "
    )
    XCTAssertEqual(custom.baseURL, "https://api.groq.com/openai/v1")
    XCTAssertEqual(custom.model, "llama-3.3-70b-versatile")
    XCTAssertNil(custom.apiKey)
    XCTAssertEqual(custom.maxAttempts, 8)
    XCTAssertEqual(custom.minSimilarity, 1)
    XCTAssertNil(custom.extraInstruction)
    XCTAssertTrue(custom.isConfigured)

    XCTAssertEqual(Settings.CustomProvider(baseURL: "localhost:11434", model: "x").baseURL, "")
    XCTAssertEqual(Settings.CustomProvider(baseURL: "ftp://example.com", model: "x").baseURL, "")
  }

  func testCredentialsNeedAnAddressAndModelButNoKey() {
    var settings = Settings()
    XCTAssertFalse(ProviderCredentials.isConfigured(for: .custom, settings: settings))

    settings.customProvider = Settings.CustomProvider(baseURL: "http://localhost:1234/v1", model: "qwen2.5")
    XCTAssertTrue(ProviderCredentials.isConfigured(for: .custom, settings: settings))
  }

  @MainActor
  func testFactoriesBuildCustomClientsWithoutAFallbackPartner() {
    var settings = Settings()
    settings.provider = .custom
    settings.enableGeminiOpenRouterFallback = true
    settings.customProvider = Settings.CustomProvider(baseURL: "http://localhost:1234/v1", model: "qwen2.5")

    let corrector = CorrectorFactory.make(settings: settings)
    let analyzer = ToneAnalyzerFactory.make(settings: settings)

    XCTAssertTrue(corrector is OpenAICorrector)
    XCTAssertEqual((corrector as? DiagnosticsProviderReporting)?.diagnosticsProvider, .custom)
    XCTAssertTrue(analyzer is OpenAIToneAnalyzer, "No fallback wrapper for Custom")
    XCTAssertEqual((analyzer as? DiagnosticsProviderReporting)?.diagnosticsProvider, .custom)
  }

  @MainActor
  func testUnsetAddressFailsWithAClearMessage() async {
    var settings = Settings()
    settings.provider = .custom

    let corrector = CorrectorFactory.make(settings: settings)

    XCTAssertTrue(corrector is FailingCorrector)
    do {
      _ = try await corrector.correct("hello")
      XCTFail("Expected an error")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Invalid Custom provider base URL")
    }
  }
}

extension CorrectorRetryAndPlaceholderTests {
  func testCustomProviderSendsOpenAIFormatToItsAddressWithoutAKey() async throws {
    var captured: URLRequest?
    MockURLProtocol.handler = { request in
      captured = request
      return Self.httpResponse(for: request, statusCode: 200, body: #"{"choices":[{"message":{"content":"hello world"}}]}"#)
    }
    let settings = Self.customSettings()
    let corrector = try OpenAICorrector(endpoint: .custom(settings), settings: settings, session: Self.makeMockSession())

    let result = try await corrector.correct("helo world")

    XCTAssertEqual(result, "hello world")
    let request = try XCTUnwrap(captured)
    XCTAssertEqual(request.url?.absoluteString, "https://mock.local/v1/chat/completions")
    XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "Local servers often need no key")
    let body = try XCTUnwrap(Self.requestBodyData(from: request))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    XCTAssertEqual(json["model"] as? String, "llama-3.3-70b")
    XCTAssertNil(json["reasoning_effort"], "OpenAI-only options stay off for other models")
  }

  func testCustomProviderSendsItsKeyWhenSet() async throws {
    var captured: URLRequest?
    MockURLProtocol.handler = { request in
      captured = request
      return Self.httpResponse(for: request, statusCode: 200, body: #"{"choices":[{"message":{"content":"hello"}}]}"#)
    }
    var settings = Self.customSettings()
    settings.customProvider.apiKey = "gsk-test"
    let corrector = try OpenAICorrector(endpoint: .custom(settings), settings: settings, session: Self.makeMockSession())

    _ = try await corrector.correct("helo")

    XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer gsk-test")
  }

  func testCustomProviderErrorsNameTheCustomProvider() async throws {
    MockURLProtocol.handler = { request in
      Self.httpResponse(for: request, statusCode: 401, body: #"{"error":{"message":"Invalid API Key"}}"#)
    }
    let settings = Self.customSettings()
    let corrector = try OpenAICorrector(endpoint: .custom(settings), settings: settings, session: Self.makeMockSession())

    do {
      _ = try await corrector.correct("helo")
      XCTFail("Expected an error")
    } catch {
      XCTAssertTrue(error is CustomProviderError)
      XCTAssertEqual(error.localizedDescription, "Custom provider unauthorized (401): check the API key")
    }
  }

  private static func customSettings() -> Settings {
    var settings = Settings(requestTimeoutSeconds: 1)
    settings.provider = .custom
    settings.customProvider = Settings.CustomProvider(baseURL: "https://mock.local/v1", model: "llama-3.3-70b", maxAttempts: 1)
    return settings
  }
}

final class CustomProviderSettingsWindowTests: XCTestCase {
  @MainActor
  func testCustomTileSavesTheAddressAndModel() throws {
    _ = NSApplication.shared
    try Settings.save(Settings())
    addTeardownBlock { try? Settings.save(Settings()) }
    let controller = SettingsWindowController(keychainServiceOverride: "com.textpolish.tests.custom-provider")
    let viewController = try XCTUnwrap(controller.viewController)

    viewController.providerTileClicked(viewController.customProviderButton)
    viewController.providerBaseURLField.stringValue = "http://localhost:11434/v1"
    viewController.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: viewController.providerBaseURLField)
    )
    viewController.providerModelField.stringValue = "llama3.2"
    viewController.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: viewController.providerModelField)
    )

    let saved = Settings.loadOrCreateDefault()
    XCTAssertEqual(saved.provider, .custom)
    XCTAssertEqual(saved.customProvider.baseURL, "http://localhost:11434/v1")
    XCTAssertEqual(saved.customProvider.model, "llama3.2")
    XCTAssertFalse(viewController.fallbackCheckbox.isEnabled, "Custom has no fallback partner")
  }
}
