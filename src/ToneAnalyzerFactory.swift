import Foundation

enum ToneAnalyzerFactory {
  @MainActor
  // Legacy hotspot: split this up before removing the suppression.
  // swiftlint:disable:next function_body_length
  static func make(settings: Settings) -> ToneAnalyzer {
    switch settings.provider {
    case .gemini:
      do {
        let primary = try GeminiToneAnalyzer(settings: settings)
        guard settings.enableGeminiOpenRouterFallback,
              hasFallbackCredentials(for: .gemini, settings: settings)
        else {
          return primary
        }
        let fallback = LazyAnalyzer {
          try OpenRouterToneAnalyzer(settings: settings)
        }
        return FallbackToneAnalyzer(
          primary: primary,
          fallback: fallback,
          primaryProvider: .gemini,
          primaryModel: settings.geminiModel,
          fallbackProvider: .openRouter,
          fallbackModel: settings.openRouterModel
        )
      } catch {
        return FailingToneAnalyzer(
          underlyingError: error,
          diagnosticsProvider: .gemini,
          diagnosticsModel: settings.geminiModel
        )
      }
    case .openRouter:
      do {
        let primary = try OpenRouterToneAnalyzer(settings: settings)
        guard settings.enableGeminiOpenRouterFallback,
              hasFallbackCredentials(for: .openRouter, settings: settings)
        else {
          return primary
        }
        let fallback = LazyAnalyzer {
          try GeminiToneAnalyzer(settings: settings)
        }
        return FallbackToneAnalyzer(
          primary: primary,
          fallback: fallback,
          primaryProvider: .openRouter,
          primaryModel: settings.openRouterModel,
          fallbackProvider: .gemini,
          fallbackModel: settings.geminiModel
        )
      } catch {
        return FailingToneAnalyzer(
          underlyingError: error,
          diagnosticsProvider: .openRouter,
          diagnosticsModel: settings.openRouterModel
        )
      }
    case .openAI:
      do {
        let primary = try OpenAIToneAnalyzer(settings: settings)
        guard settings.enableGeminiOpenRouterFallback,
              hasFallbackCredentials(for: .openAI, settings: settings)
        else {
          return primary
        }
        let fallback = LazyAnalyzer {
          try AnthropicToneAnalyzer(settings: settings)
        }
        return FallbackToneAnalyzer(
          primary: primary,
          fallback: fallback,
          primaryProvider: .openAI,
          primaryModel: settings.openAIModel,
          fallbackProvider: .anthropic,
          fallbackModel: settings.anthropicModel
        )
      } catch {
        return FailingToneAnalyzer(
          underlyingError: error,
          diagnosticsProvider: .openAI,
          diagnosticsModel: settings.openAIModel
        )
      }
    case .anthropic:
      do {
        let primary = try AnthropicToneAnalyzer(settings: settings)
        guard settings.enableGeminiOpenRouterFallback,
              hasFallbackCredentials(for: .anthropic, settings: settings)
        else {
          return primary
        }
        let fallback = LazyAnalyzer {
          try OpenAIToneAnalyzer(settings: settings)
        }
        return FallbackToneAnalyzer(
          primary: primary,
          fallback: fallback,
          primaryProvider: .anthropic,
          primaryModel: settings.anthropicModel,
          fallbackProvider: .openAI,
          fallbackModel: settings.openAIModel
        )
      } catch {
        return FailingToneAnalyzer(
          underlyingError: error,
          diagnosticsProvider: .anthropic,
          diagnosticsModel: settings.anthropicModel
        )
      }
    case .custom:
      do {
        return try OpenAIToneAnalyzer(endpoint: .custom(settings), settings: settings)
      } catch {
        return FailingToneAnalyzer(
          underlyingError: error,
          diagnosticsProvider: .custom,
          diagnosticsModel: settings.customProvider.model
        )
      }
    }
  }

  private static func hasFallbackCredentials(for primary: Settings.Provider, settings: Settings) -> Bool {
    switch primary {
    case .openAI:
      return ProviderCredentials.isConfigured(for: .anthropic, settings: settings)
    case .anthropic:
      return ProviderCredentials.isConfigured(for: .openAI, settings: settings)
    case .gemini:
      return ProviderCredentials.isConfigured(for: .openRouter, settings: settings)
    case .openRouter:
      return ProviderCredentials.isConfigured(for: .gemini, settings: settings)
    case .custom:
      return false
    }
  }
}

/// Wrapper for lazy initialization of analyzer.
/// Safety: accessed through controller-owned analyzer instances; no concurrent calls are made.
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

/// Analyzer that tries primary first, then falls back to secondary on failure.
/// Safety: mutable state tracks the latest request only; callers do not invoke `analyze` concurrently.
final class FallbackToneAnalyzer: ToneAnalyzer, DiagnosticsProviderReporting, RetryReporting, @unchecked Sendable {
  private let primary: ToneAnalyzer
  private let fallback: ToneAnalyzer
  private let primaryProvider: Settings.Provider
  private let primaryModel: String
  private let fallbackProvider: Settings.Provider
  private let fallbackModel: String
  private var lastProvider: Settings.Provider
  private var lastModel: String
  private var lastRetryCountValue = 0

  init(
    primary: ToneAnalyzer,
    fallback: ToneAnalyzer,
    primaryProvider: Settings.Provider,
    primaryModel: String,
    fallbackProvider: Settings.Provider,
    fallbackModel: String
  ) {
    self.primary = primary
    self.fallback = fallback
    self.primaryProvider = primaryProvider
    self.primaryModel = primaryModel
    self.fallbackProvider = fallbackProvider
    self.fallbackModel = fallbackModel
    self.lastProvider = primaryProvider
    self.lastModel = primaryModel
  }

  var diagnosticsProvider: Settings.Provider {
    lastProvider
  }

  var diagnosticsModel: String {
    lastModel
  }

  var lastRetryCount: Int {
    lastRetryCountValue
  }

  private func updateRetryCount(from analyzer: ToneAnalyzer) {
    lastRetryCountValue = (analyzer as? RetryReporting)?.lastRetryCount ?? 0
  }

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    do {
      lastProvider = primaryProvider
      lastModel = primaryModel
      let result = try await primary.analyze(text)
      updateRetryCount(from: primary)
      return result
    } catch {
      updateRetryCount(from: primary)
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
        case .textTooShort, .textTooLong:
          // Input validation won't be fixed by switching providers.
          throw error
        case .rateLimited, .requestFailed, .emptyResponse, .invalidResponse, nil:
          // Fallback on API errors
          break
        }
      }
      // Fallback on network errors, API errors, or any other error (except CancellationError)
      lastProvider = fallbackProvider
      lastModel = fallbackModel
      do {
        let result = try await fallback.analyze(text)
        updateRetryCount(from: fallback)
        return result
      } catch {
        updateRetryCount(from: fallback)
        throw error
      }
    }
  }
}

struct FailingToneAnalyzer: ToneAnalyzer, DiagnosticsProviderReporting, @unchecked Sendable {
  let underlyingError: Error
  let diagnosticsProvider: Settings.Provider
  let diagnosticsModel: String

  func analyze(_ text: String) async throws -> ToneAnalysisResult {
    throw underlyingError
  }
}
