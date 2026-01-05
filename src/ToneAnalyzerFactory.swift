import Foundation

enum ToneAnalyzerFactory {
  @MainActor
  static func make(settings: Settings) -> ToneAnalyzer {
    switch settings.provider {
    case .gemini:
      do {
        return try GeminiToneAnalyzer(settings: settings)
      } catch {
        return FailingToneAnalyzer(underlyingError: error)
      }
    case .openRouter:
      do {
        return try OpenRouterToneAnalyzer(settings: settings)
      } catch {
        return FailingToneAnalyzer(underlyingError: error)
      }
    }
  }
}

struct FailingToneAnalyzer: ToneAnalyzer, @unchecked Sendable {
  let underlyingError: Error

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    throw underlyingError
  }
}
