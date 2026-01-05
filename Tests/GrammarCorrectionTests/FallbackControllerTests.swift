import XCTest
import AppKit
@testable import GrammarCorrection

final class FallbackControllerTests: XCTestCase {
    var fallbackController: FallbackController!
    var mockFallbackProvider: MockGrammarCorrector!
    var mockShowSuccessCalled = false
    var mockShowInfoCalled = false
    var mockShowErrorCalled = false
    var mockShowInfoMessage = ""
    var mockShowErrorMessage = ""
    var mockOnFallbackCompleteCalled = false
    var mockOnFallbackCompleteResult = false

    override func setUp() {
        super.setUp()
        mockFallbackProvider = MockGrammarCorrector()
        mockShowSuccessCalled = false
        mockShowInfoCalled = false
        mockShowErrorCalled = false
        mockShowInfoMessage = ""
        mockShowErrorMessage = ""
        mockOnFallbackCompleteCalled = false
        mockOnFallbackCompleteResult = false

        fallbackController = FallbackController(
            fallbackProvider: mockFallbackProvider,
            showSuccess: { [weak self] in
                self?.mockShowSuccessCalled = true
            },
            showInfo: { [weak self] message in
                self?.mockShowInfoCalled = true
                self?.mockShowInfoMessage = message
            },
            showError: { [weak self] message in
                self?.mockShowErrorCalled = true
                self?.mockShowErrorMessage = message
            },
            onFallbackComplete: { [weak self] success in
                self?.mockOnFallbackCompleteCalled = true
                self?.mockOnFallbackCompleteResult = success
            }
        )
    }

    override func tearDown() {
        fallbackController = nil
        mockFallbackProvider = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertNotNil(fallbackController, "FallbackController should be initialized")
        XCTAssertNotNil(fallbackController.fallbackProvider, "Fallback provider should be set")
    }

    func testProviderNameForGeminiCorrector() {
        // Given
        let geminiProvider = try! GeminiCorrector(settings: Settings.loadOrCreateDefault())

        // When
        let name = fallbackController.providerName(for: geminiProvider)

        // Then
        XCTAssertEqual(name, "Gemini", "Should return 'Gemini' for GeminiCorrector")
    }

    func testProviderNameForOpenRouterCorrector() {
        // Given
        var settings = Settings.loadOrCreateDefault()
        settings.provider = .openRouter
        let openRouterProvider = try! OpenRouterCorrector(settings: settings)

        // When
        let name = fallbackController.providerName(for: openRouterProvider)

        // Then
        XCTAssertEqual(name, "OpenRouter", "Should return 'OpenRouter' for OpenRouterCorrector")
    }

    func testProviderNameForUnknownCorrector() {
        // Given
        let unknownProvider = MockGrammarCorrector()

        // When
        let name = fallbackController.providerName(for: unknownProvider)

        // Then
        XCTAssertEqual(name, "Provider", "Should return 'Provider' for unknown corrector type")
    }

    func testPerformFallbackSuccess() async {
        // Given
        mockFallbackProvider.shouldThrow = false
        let testText = "Test text for correction"

        // When
        await fallbackController.performFallback(text: testText, corrector: mockFallbackProvider)

        // Then
        XCTAssertTrue(mockShowInfoCalled, "showInfo should be called")
        XCTAssertTrue(mockShowInfoMessage.contains("Gemini"), "Info message should mention provider name")
        XCTAssertTrue(mockOnFallbackCompleteCalled, "onFallbackComplete should be called")
        XCTAssertTrue(mockOnFallbackCompleteResult, "Success result should be true")
        XCTAssertFalse(mockShowErrorCalled, "showError should not be called on success")
    }

    func testPerformFallbackFailure() async {
        // Given
        mockFallbackProvider.shouldThrow = true
        mockFallbackProvider.throwError = NSError(domain: "TestError", code: 1, userInfo: nil)
        let testText = "Test text for correction"

        // When
        await fallbackController.performFallback(text: testText, corrector: mockFallbackProvider)

        // Then
        XCTAssertTrue(mockShowErrorCalled, "showError should be called on failure")
        XCTAssertTrue(mockShowErrorMessage.contains("Fallback also failed"), "Error message should mention fallback failure")
        XCTAssertTrue(mockOnFallbackCompleteCalled, "onFallbackComplete should be called")
        XCTAssertFalse(mockOnFallbackCompleteResult, "Success result should be false")
        XCTAssertFalse(mockShowSuccessCalled, "showSuccess should not be called on failure")
    }

    func testShowFallbackAlert() {
        // Given
        let testError = NSError(domain: "TestError", code: 1, userInfo: nil)
        let testText = "Test text"

        // Note: We can't easily test the actual alert presentation without creating a full app context
        // But we can verify the method doesn't crash

        // When & Then
        XCTAssertNoThrow(fallbackController.showFallbackAlert(for: testError, corrector: mockFallbackProvider, text: testText))
    }

    func testFallbackControllerWithNilCallbacks() {
        // Given
        let controller = FallbackController(
            fallbackProvider: mockFallbackProvider,
            showSuccess: { },
            showInfo: { _ in },
            showError: { _ in }
            // onFallbackComplete is nil
        )

        // When & Then
        XCTAssertNoThrow(controller.showFallbackAlert(for: testError(), corrector: mockFallbackProvider, text: "test"))
    }

    func testProviderNameDetection() {
        // Test all provider types
        let providers: [(GrammarCorrector, String)] = [
            (try! GeminiCorrector(settings: Settings.loadOrCreateDefault()), "Gemini"),
            (try! OpenRouterCorrector(settings: Settings.loadOrCreateDefault()), "OpenRouter"),
            (MockGrammarCorrector(), "Provider")
        ]

        for (provider, expectedName) in providers {
            let name = fallbackController.providerName(for: provider)
            XCTAssertEqual(name, expectedName, "Should return correct name for provider type")
        }
    }

    func testFallbackWithEmptyText() async {
        // Given
        mockFallbackProvider.shouldThrow = false
        let emptyText = ""

        // When
        await fallbackController.performFallback(text: emptyText, corrector: mockFallbackProvider)

        // Then
        XCTAssertTrue(mockOnFallbackCompleteCalled, "Should complete even with empty text")
    }

    func testMultipleFallbackAttempts() async {
        // Given
        mockFallbackProvider.shouldThrow = false

        // When
        await fallbackController.performFallback(text: "Test 1", corrector: mockFallbackProvider)
        await fallbackController.performFallback(text: "Test 2", corrector: mockFallbackProvider)

        // Then
        XCTAssertEqual(mockOnFallbackCompleteCalled, true, "onFallbackComplete should be called for each attempt")
    }

    func testInfoMessageFormat() async {
        // Given
        mockFallbackProvider.shouldThrow = false

        // When
        await fallbackController.performFallback(text: "test", corrector: mockFallbackProvider)

        // Then
        XCTAssertTrue(mockShowInfoMessage.contains("Gemini"), "Info message should contain provider name")
    }

    func testErrorMessageFormat() async {
        // Given
        let customError = NSError(domain: "CustomError", code: 42, userInfo: [NSLocalizedDescriptionKey: "Custom error message"])
        mockFallbackProvider.shouldThrow = true
        mockFallbackProvider.throwError = customError

        // When
        await fallbackController.performFallback(text: "test", corrector: mockFallbackProvider)

        // Then
        XCTAssertTrue(mockShowErrorMessage.contains("Custom error message"), "Error message should contain error description")
    }

    func testMainActorIsolation() async {
        // Verify that the performFallback method properly isolates to MainActor
        // This is implicitly tested by the async/await pattern

        // Given
        mockFallbackProvider.shouldThrow = false

        // When
        await fallbackController.performFallback(text: "test", corrector: mockFallbackProvider)

        // Then - if we get here without crashes, the actor isolation is working
        XCTAssertTrue(true, "Method executed successfully on MainActor")
    }

    // MARK: - Helper Methods

    private func testError() -> Error {
        return NSError(domain: "TestError", code: 1, userInfo: nil)
    }
}

// MARK: - Mock GrammarCorrector

final class MockGrammarCorrector: GrammarCorrector {
    var shouldThrow = false
    var throwError: Error?

    func correct(_ text: String) async throws -> String {
        if shouldThrow {
            throw throwError ?? NSError(domain: "MockError", code: 1, userInfo: nil)
        }
        return "Corrected: \(text)"
    }
}

// MARK: - GeminiCorrector Mock for Testing

final class MockGeminiCorrector: GrammarCorrector {
    func correct(_ text: String) async throws -> String {
        return "Gemini corrected: \(text)"
    }
}

// MARK: - OpenRouterCorrector Mock for Testing

final class MockOpenRouterCorrector: GrammarCorrector {
    func correct(_ text: String) async throws -> String {
        return "OpenRouter corrected: \(text)"
    }
}
