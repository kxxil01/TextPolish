import Foundation

enum CorrectorFactory {
  @MainActor
  static func make(settings: Settings) -> GrammarCorrector {
    switch settings.provider {
    case .gemini:
      do {
        return try GeminiCorrector(settings: settings)
      } catch {
        return FailingCorrector(
          underlyingError: error,
          diagnosticsProvider: .gemini,
          diagnosticsModel: settings.geminiModel
        )
      }
    case .openRouter:
      do {
        return try OpenRouterCorrector(settings: settings)
      } catch {
        return FailingCorrector(
          underlyingError: error,
          diagnosticsProvider: .openRouter,
          diagnosticsModel: settings.openRouterModel
        )
      }
    case .openAI:
      do {
        return try OpenAICorrector(settings: settings)
      } catch {
        return FailingCorrector(
          underlyingError: error,
          diagnosticsProvider: .openAI,
          diagnosticsModel: settings.openAIModel
        )
      }
    case .anthropic:
      do {
        return try AnthropicCorrector(settings: settings)
      } catch {
        return FailingCorrector(
          underlyingError: error,
          diagnosticsProvider: .anthropic,
          diagnosticsModel: settings.anthropicModel
        )
      }
    }
  }
}

struct FailingCorrector: GrammarCorrector, DiagnosticsProviderReporting, @unchecked Sendable {
  let underlyingError: Error
  let diagnosticsProvider: Settings.Provider
  let diagnosticsModel: String

  func correct(_ text: String) async throws -> String {
    throw underlyingError
  }
}
