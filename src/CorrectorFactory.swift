import Foundation

enum CorrectorFactory {
  @MainActor
  static func make(settings: Settings) -> GrammarCorrector {
    switch settings.provider {
    case .gemini:
      do {
        return try GeminiCorrector(settings: settings)
      } catch {
        return FailingCorrector(underlyingError: error)
      }
    case .openRouter:
      do {
        return try OpenRouterCorrector(settings: settings)
      } catch {
        return FailingCorrector(underlyingError: error)
      }
    }
  }
}

struct FailingCorrector: GrammarCorrector, @unchecked Sendable {
  let underlyingError: Error

  func correct(_ text: String) async throws -> String {
    throw underlyingError
  }
}
