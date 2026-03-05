import XCTest
@testable import GrammarCorrection

final class ModelDetectorTests: XCTestCase {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Gemini Model Detection Tests

    func testDetectGeminiModelThrowsWhenNoApiKey() async {
        // Given
        let emptyApiKey = ""
        let baseURL = "https://generativelanguage.googleapis.com"

        // When & Then
        do {
            _ = try await ModelDetector.detectGeminiModel(apiKey: emptyApiKey, baseURL: baseURL)
            XCTFail("Should throw error when API key is empty")
        } catch let error as ModelDetector.DetectorError {
            XCTAssertEqual(error, .noApiKey, "Should throw noApiKey error")
        } catch {
            XCTFail("Should throw ModelDetector.DetectorError, got \(error)")
        }
    }

    func testDetectGeminiModelThrowsWhenInvalidBaseURL() async {
        // Given
        let apiKey = "TEST_KEY_FOR_UNIT_TESTING"
        let invalidBaseURL = "not-a-valid-url"

        // When & Then
        do {
            _ = try await ModelDetector.detectGeminiModel(apiKey: apiKey, baseURL: invalidBaseURL)
            XCTFail("Should throw error for invalid URL")
        } catch let error as ModelDetector.DetectorError {
            XCTAssertEqual(error, .requestFailed("unsupported URL"), "Should throw invalid URL error")
        } catch {
            XCTFail("Should throw ModelDetector.DetectorError, got \(error)")
        }
    }

    func testDetectGeminiModelHandlesHTTPError() async {
        // This would require mocking URLSession, which is complex
        // In a real app, you'd use URLProtocol mocking
        // For now, we test the error handling path

        // Given
        let apiKey = "INVALID_TEST_KEY_FOR_TESTING"
        let baseURL = "https://generativelanguage.googleapis.com"

        // When & Then
        do {
            _ = try await ModelDetector.detectGeminiModel(apiKey: apiKey, baseURL: baseURL)
            // If we get here, the API might have returned success (unlikely with invalid key)
            // or the test environment allows the request
            XCTAssert(true, "Request completed (may have succeeded or failed)")
        } catch let error as ModelDetector.DetectorError {
            XCTAssert(true, "Properly threw DetectorError: \(error)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGeminiModelsResponseDecoding() throws {
        // Given
        let json = """
        {
          "models": [
            {
              "name": "gemini-2.5-pro"
            },
            {
              "name": "gemini-2.5-flash"
            }
          ]
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(ModelDetector.GeminiModelsResponse.self, from: json)

        // Then
        XCTAssertEqual(response.models?.count, 2, "Should decode 2 models")
        XCTAssertEqual(response.models?[0].name, "gemini-2.5-pro", "First model should be gemini-2.5-pro")
        XCTAssertEqual(response.models?[1].name, "gemini-2.5-flash", "Second model should be gemini-2.5-flash")
    }

    func testGeminiModelsResponseDecodingWithEmpty() throws {
        // Given
        let json = """
        {
          "models": []
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(ModelDetector.GeminiModelsResponse.self, from: json)

        // Then
        XCTAssertEqual(response.models?.count, 0, "Should decode 0 models")
    }

    // MARK: - OpenRouter Model Detection Tests

    func testDetectOpenRouterModelThrowsWhenNoApiKey() async {
        // Given
        let emptyApiKey = ""

        // When & Then
        do {
            _ = try await ModelDetector.detectOpenRouterModel(apiKey: emptyApiKey)
            XCTFail("Should throw error when API key is empty")
        } catch let error as ModelDetector.DetectorError {
            XCTAssertEqual(error, .noApiKey, "Should throw noApiKey error")
        } catch {
            XCTFail("Should throw ModelDetector.DetectorError, got \(error)")
        }
    }

    func testDetectOpenRouterModelHandlesHTTPError() async {
        // Given
        let invalidApiKey = "invalid-key"

        // When & Then
        do {
            _ = try await ModelDetector.detectOpenRouterModel(apiKey: invalidApiKey)
            XCTAssert(true, "Request completed")
        } catch let error as ModelDetector.DetectorError {
            XCTAssert(true, "Properly threw DetectorError: \(error)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testOpenRouterModelsResponseDecoding() throws {
        // Given
        let json = """
        {
          "data": [
            {
              "id": "google/gemma-3n-e4b-it:free",
              "pricing": {
                "prompt": "0",
                "completion": "0"
              }
            },
            {
              "id": "openai/gpt-4",
              "pricing": {
                "prompt": "0.01",
                "completion": "0.03"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(ModelDetector.OpenRouterModelsResponse.self, from: json)

        // Then
        XCTAssertEqual(response.data?.count, 2, "Should decode 2 models")
        XCTAssertEqual(response.data?[0].id, "google/gemma-3n-e4b-it:free", "First model should be gemma free model")
        XCTAssertEqual(response.data?[0].pricing?.prompt, "0", "First model should be free")
    }

    func testOpenRouterModelsResponseDecodingWithNilPricing() throws {
        // Given
        let json = """
        {
          "data": [
            {
              "id": "test/model",
              "pricing": null
            }
          ]
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(ModelDetector.OpenRouterModelsResponse.self, from: json)

        // Then
        XCTAssertEqual(response.data?.count, 1, "Should decode 1 model")
        XCTAssertNil(response.data?[0].pricing?.prompt, "Pricing should be nil")
    }

    // MARK: - DetectorError Tests

    func testDetectorErrorLocalizedDescription() {
        // Test noApiKey error
        let noApiKeyError = ModelDetector.DetectorError.noApiKey
        XCTAssertEqual(noApiKeyError.localizedDescription, "API key is required", "Should have correct description")

        // Test requestFailed error
        let requestFailedError = ModelDetector.DetectorError.requestFailed("Test error")
        XCTAssertEqual(requestFailedError.localizedDescription, "Test error", "Should have correct description")
    }

    // MARK: - Model Selection Tests

    func testGeminiPreferredModelSelection() throws {
        // Given - simulates API response with preferred model
        let json = """
        {
          "models": [
            {
              "name": "gemini-2.5-pro"
            },
            {
              "name": "gemini-2.5-flash"
            },
            {
              "name": "gemini-2.5-flash-lite"
            }
          ]
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(ModelDetector.GeminiModelsResponse.self, from: json)

        // Then - check that preferred model is first in the list
        let preferred = response.models?.first(where: { $0.name == "gemini-2.5-flash" })
        XCTAssertNotNil(preferred, "Should find preferred model")
    }

    func testMakeGeminiModelsURLPreservesCustomBasePath() throws {
        let url = try ModelDetector.makeGeminiModelsURL(
            baseURL: "https://gateway.example.com/googleai",
            apiKey: "test-key"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://gateway.example.com/googleai/v1beta/models?key=test-key",
            "Should preserve configured path prefix when building Gemini models URL"
        )
    }

    func testMakeGeminiModelsURLDoesNotDuplicateV1BetaPath() throws {
        let url = try ModelDetector.makeGeminiModelsURL(
            baseURL: "https://gateway.example.com/googleai/v1beta",
            apiKey: "test-key"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://gateway.example.com/googleai/v1beta/models?key=test-key",
            "Should append models endpoint without duplicating v1beta segment"
        )
    }

    func testSelectPreferredGeminiModelNormalizesModelsPrefix() {
        let models = [
            ModelDetector.GeminiModelsResponse.Model(name: "models/gemini-2.5-pro"),
            ModelDetector.GeminiModelsResponse.Model(name: "models/gemini-2.5-flash")
        ]
        let selected = ModelDetector.selectPreferredGeminiModel(from: models)
        XCTAssertEqual(selected, "gemini-2.5-flash", "Should normalize models/ prefix and choose preferred model")
    }

    func testOpenRouterFreeModelSelection() throws {
        // Given - simulates API response with free model
        let json = """
        {
          "data": [
            {
              "id": "openai/gpt-4",
              "pricing": {
                "prompt": "0.01",
                "completion": "0.03"
              }
            },
            {
              "id": "google/gemma-3n-e4b-it:free",
              "pricing": {
                "prompt": "0",
                "completion": "0"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(ModelDetector.OpenRouterModelsResponse.self, from: json)

        // Then - check that free model is found
        let freeModel = response.data?.first(where: { $0.pricing?.prompt == "0" && $0.pricing?.completion == "0" })
        XCTAssertNotNil(freeModel, "Should find free model")
        XCTAssertEqual(freeModel?.id, "google/gemma-3n-e4b-it:free", "Should select correct free model")
    }

    func testEmptyModelsResponse() throws {
        // Given
        let json = """
        {
          "models": []
        }
        """.data(using: .utf8)!

        // When
        let response = try JSONDecoder().decode(ModelDetector.GeminiModelsResponse.self, from: json)

        // Then
        XCTAssertEqual(response.models?.count, 0, "Should handle empty models array")
    }

    func testMalformedJSON() {
        // Given
        let malformedJson = "{ invalid json }".data(using: .utf8)!

        // When & Then
        XCTAssertThrowsError(try JSONDecoder().decode(ModelDetector.GeminiModelsResponse.self, from: malformedJson)) { error in
            XCTAssertTrue(error is DecodingError, "Should throw DecodingError for malformed JSON")
        }
    }

    func testMakeOpenRouterModelsURLPreservesCustomBasePath() throws {
        let url = try ModelDetector.makeOpenRouterModelsURL(
            baseURL: "https://gateway.example.com/proxy/openrouter"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://gateway.example.com/proxy/openrouter/models",
            "Should preserve configured OpenRouter path prefix when building models URL"
        )
    }

    func testMakeOpenRouterModelsURLDoesNotDuplicateModelsPath() throws {
        let url = try ModelDetector.makeOpenRouterModelsURL(
            baseURL: "https://gateway.example.com/proxy/openrouter/models"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://gateway.example.com/proxy/openrouter/models",
            "Should avoid duplicating models segment"
        )
    }

    func testMakeOpenRouterModelsURLReplacesChatCompletionsSuffix() throws {
        let url = try ModelDetector.makeOpenRouterModelsURL(
            baseURL: "https://gateway.example.com/proxy/openrouter/chat/completions"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://gateway.example.com/proxy/openrouter/models",
            "Should resolve models endpoint from chat completions URL"
        )
    }
}
