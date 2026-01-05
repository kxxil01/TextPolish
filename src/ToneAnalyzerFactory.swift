import Foundation

enum ToneAnalyzerFactory {
  @MainActor
  static func make(settings: Settings) -> ToneAnalyzer {
    switch settings.provider {
    case .gemini:
      do {
        let primary = try GeminiToneAnalyzer(settings: settings)
        // Lazy fallback - only initialize if actually needed
        let fallback = LazyAnalyzer {
          try OpenRouterToneAnalyzer(settings: settings)
        }
        return FallbackToneAnalyzer(primary: primary, fallback: fallback)
      } catch {
        return FailingToneAnalyzer(underlyingError: error)
      }
    case .openRouter:
      do {
        let primary = try OpenRouterToneAnalyzer(settings: settings)
        // Lazy fallback - only initialize if actually needed
        let fallback = LazyAnalyzer {
          try GeminiToneAnalyzer(settings: settings)
        }
        return FallbackToneAnalyzer(primary: primary, fallback: fallback)
      } catch {
        return FailingToneAnalyzer(underlyingError: error)
      }
    }
  }
}

/// Wrapper for lazy initialization of analyzer
final class LazyAnalyzer: ToneAnalyzer, @unchecked Sendable {
  private let factory: () throws -> ToneAnalyzer
  private var cached: ToneAnalyzer?

  init(factory: @escaping () throws -> ToneAnalyzer) {
    self.factory = factory
  }

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    if let cached = cached {
      return try await cached.analyze(text)
    }
    let analyzer = try factory()
    cached = analyzer
    return try await analyzer.analyze(text)
  }
}

/// Analyzer that tries primary first, then falls back to secondary on failure
struct FallbackToneAnalyzer: ToneAnalyzer, @unchecked Sendable {
  private let primary: ToneAnalyzer
  private let fallback: ToneAnalyzer

  init(primary: ToneAnalyzer, fallback: ToneAnalyzer) {
    self.primary = primary
    self.fallback = fallback
  }

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    do {
      return try await primary.analyze(text)
    } catch {
      // Don't fallback on cancellation errors
      if error is CancellationError {
        throw error
      }

      // Only fallback on actual API errors, not validation errors
      if error is ToneAnalysisError {
        let toneError = error as? ToneAnalysisError
        switch toneError {
        case .missingApiKey, .invalidBaseURL, .invalidModelName:
          // Don't fallback on configuration errors
          throw error
        case .rateLimited, .requestFailed, .emptyResponse, .invalidResponse, .textTooShort, .textTooLong, nil:
          // Fallback on API errors
          break
        }
      }
      // Fallback on network errors, API errors, or any other error (except CancellationError)
      return try await fallback.analyze(text)
    }
  }
}

struct FailingToneAnalyzer: ToneAnalyzer, @unchecked Sendable {
  let underlyingError: Error

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    throw underlyingError
  }
}
