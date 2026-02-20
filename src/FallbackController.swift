import Foundation
import AppKit

final class FallbackController {
    public let fallbackProvider: GrammarCorrector
    private let showSuccess: () -> Void
    private let showInfo: (String) -> Void
    private let showError: (String) -> Void
    private let onFallbackComplete: ((Bool) -> Void)?

    init(
        fallbackProvider: GrammarCorrector,
        showSuccess: @escaping () -> Void,
        showInfo: @escaping (String) -> Void,
        showError: @escaping (String) -> Void,
        onFallbackComplete: ((Bool) -> Void)? = nil
    ) {
        self.fallbackProvider = fallbackProvider
        self.showSuccess = showSuccess
        self.showInfo = showInfo
        self.showError = showError
        self.onFallbackComplete = onFallbackComplete
    }

    func shouldAttemptFallback(for error: Error, corrector: GrammarCorrector) -> Bool {
        // Don't show alert in test environment to avoid blocking CI/CD
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil {
            NSLog("[TextPolish] Fallback alert suppressed in test environment: \(error)")
            return false
        }
        #endif

        let alert = NSAlert()
        alert.messageText = "Primary Provider Failed"
        alert.informativeText = "Try using \(providerName(for: fallbackProvider)) instead?\n\nError: \(error.localizedDescription)"
        alert.alertStyle = .informational

        // Add buttons
        let tryButton = alert.addButton(withTitle: "Try \(providerName(for: fallbackProvider))")
        tryButton.keyEquivalent = "\r" // Return key

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}" // Escape key

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    func showFallbackAlert(for error: Error, corrector: GrammarCorrector, text: String) {
        if shouldAttemptFallback(for: error, corrector: corrector) {
            Task {
                _ = await performFallback(text: text, corrector: corrector)
            }
        }
    }

    @discardableResult
    func performFallback(text: String, corrector: GrammarCorrector) async -> Result<String, Error> {
        do {
            let corrected = try await fallbackProvider.correct(text)

            await MainActor.run {
                showSuccess()
                showInfo("Used \(providerName(for: fallbackProvider)) as fallback")
                onFallbackComplete?(true)
            }
            return .success(corrected)
        } catch {
            await MainActor.run {
                showError("Fallback also failed: \(error.localizedDescription)")
                onFallbackComplete?(false)
            }
            return .failure(error)
        }
    }

    public func providerName(for corrector: GrammarCorrector) -> String {
        guard let reporting = corrector as? DiagnosticsProviderReporting else {
            return "Provider"
        }

        switch reporting.diagnosticsProvider {
        case .gemini:
            return "Gemini"
        case .openRouter:
            return "OpenRouter"
        case .openAI:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        }
    }
}
