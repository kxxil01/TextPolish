import Foundation
import AppKit

final class FallbackController {
    public let fallbackProvider: GrammarCorrector
    private var originalCorrector: GrammarCorrector?
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

    func showFallbackAlert(for error: Error, corrector: GrammarCorrector, text: String) {
        // Don't show alert in test environment to avoid blocking CI/CD
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil {
            NSLog("[TextPolish] Fallback alert suppressed in test environment: \(error)")
            return
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

        if response == .alertFirstButtonReturn {
            Task {
                await performFallback(text: text, corrector: corrector)
            }
        }
    }

    func performFallback(text: String, corrector: GrammarCorrector) async {
        do {
            _ = try await fallbackProvider.correct(text)

            await MainActor.run {
                showInfo("Used \(providerName(for: fallbackProvider)) as fallback")
                onFallbackComplete?(true)
            }
        } catch {
            await MainActor.run {
                showError("Fallback also failed: \(error.localizedDescription)")
                onFallbackComplete?(false)
            }
        }
    }

    public func providerName(for corrector: GrammarCorrector) -> String {
        if corrector is GeminiCorrector {
            return "Gemini"
        } else if corrector is OpenRouterCorrector {
            return "OpenRouter"
        }
        return "Provider"
    }
}
