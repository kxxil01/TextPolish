import Foundation

enum DiagnosticsOperation: String, Sendable {
  case correction = "Correction"
  case toneAnalysis = "Tone Analysis"
}

enum DiagnosticsStatus: String, Sendable {
  case success = "Success"
  case note = "Note"
  case error = "Error"
}

struct DiagnosticsSnapshot: Sendable {
  let timestamp: Date
  let operation: DiagnosticsOperation
  let provider: Settings.Provider
  let model: String
  let latencySeconds: Double?
  let retryCount: Int
  let fallbackCount: Int
  let status: DiagnosticsStatus
  let message: String?
}

enum ProviderHealthState: String, Sendable {
  case ok = "OK"
  case degraded = "Degraded"
  case error = "Error"
  case unknown = "Unknown"
}

struct ProviderHealthStatus: Sendable {
  let state: ProviderHealthState
  let message: String
  let updatedAt: Date
}

protocol RetryReporting: Sendable {
  var lastRetryCount: Int { get }
}

protocol DiagnosticsProviderReporting: Sendable {
  var diagnosticsProvider: Settings.Provider { get }
  var diagnosticsModel: String { get }
}

extension Notification.Name {
  static let diagnosticsUpdated = Notification.Name("TextPolishDiagnosticsUpdated")
}

@MainActor
final class DiagnosticsStore {
  static let shared = DiagnosticsStore()

  private(set) var lastSnapshot: DiagnosticsSnapshot?
  private(set) var healthStatus = ProviderHealthStatus(
    state: .unknown,
    message: "No recent activity",
    updatedAt: Date()
  )

  func recordSuccess(
    operation: DiagnosticsOperation,
    provider: Settings.Provider,
    model: String,
    latencySeconds: Double,
    retryCount: Int,
    fallbackCount: Int,
    note: String? = nil
  ) {
    let snapshot = DiagnosticsSnapshot(
      timestamp: Date(),
      operation: operation,
      provider: provider,
      model: model,
      latencySeconds: latencySeconds,
      retryCount: retryCount,
      fallbackCount: fallbackCount,
      status: note == nil ? .success : .note,
      message: note
    )
    lastSnapshot = snapshot
    healthStatus = ProviderHealthStatus(state: .ok, message: "OK", updatedAt: Date())
    NotificationCenter.default.post(name: .diagnosticsUpdated, object: self)
  }

  func recordNote(
    operation: DiagnosticsOperation,
    provider: Settings.Provider,
    model: String,
    latencySeconds: Double?,
    retryCount: Int,
    fallbackCount: Int,
    message: String,
    updateHealth: Bool
  ) {
    let snapshot = DiagnosticsSnapshot(
      timestamp: Date(),
      operation: operation,
      provider: provider,
      model: model,
      latencySeconds: latencySeconds,
      retryCount: retryCount,
      fallbackCount: fallbackCount,
      status: .note,
      message: message
    )
    lastSnapshot = snapshot
    if updateHealth {
      healthStatus = ProviderHealthStatus(state: .ok, message: "OK", updatedAt: Date())
    }
    NotificationCenter.default.post(name: .diagnosticsUpdated, object: self)
  }

  func recordFailure(
    operation: DiagnosticsOperation,
    provider: Settings.Provider,
    model: String,
    latencySeconds: Double?,
    retryCount: Int,
    fallbackCount: Int,
    message: String,
    error: Error?
  ) {
    let snapshot = DiagnosticsSnapshot(
      timestamp: Date(),
      operation: operation,
      provider: provider,
      model: model,
      latencySeconds: latencySeconds,
      retryCount: retryCount,
      fallbackCount: fallbackCount,
      status: .error,
      message: message
    )
    lastSnapshot = snapshot
    if let error, let status = providerHealthStatus(for: error) {
      healthStatus = status
    }
    NotificationCenter.default.post(name: .diagnosticsUpdated, object: self)
  }

  func formattedSnapshot() -> String {
    guard let snapshot = lastSnapshot else {
      return "No activity recorded yet."
    }

    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    var lines: [String] = [
      "Operation: \(snapshot.operation.rawValue)",
      "Provider: \(providerDisplayName(snapshot.provider))",
      "Model: \(snapshot.model)",
      "Result: \(snapshot.status.rawValue)",
    ]

    if let latency = snapshot.latencySeconds {
      lines.append("Latency: \(formatLatency(latency))")
    }
    lines.append("Retries: \(snapshot.retryCount)")
    lines.append("Fallbacks: \(snapshot.fallbackCount)")

    if let message = snapshot.message, !message.isEmpty {
      let prefix = snapshot.status == .error ? "Error" : "Note"
      lines.append("\(prefix): \(message)")
    }

    lines.append("Updated: \(formatter.string(from: snapshot.timestamp))")
    return lines.joined(separator: "\n")
  }

  func healthMenuTitle() -> String {
    let label = healthStatus.state.rawValue
    if healthStatus.state == .ok {
      return "Health: \(label)"
    }
    return "Health: \(healthStatus.message)"
  }

  func healthToolTip() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return "Last update: \(formatter.string(from: healthStatus.updatedAt))"
  }

  private func formatLatency(_ seconds: Double) -> String {
    if seconds < 1.0 {
      let ms = Int(seconds * 1000.0)
      return "\(ms) ms"
    }
    return String(format: "%.2f s", seconds)
  }

  private func providerDisplayName(_ provider: Settings.Provider) -> String {
    switch provider {
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

  private func providerHealthStatus(for error: Error) -> ProviderHealthStatus? {
    let now = Date()

    if let geminiError = error as? GeminiCorrector.GeminiError {
      switch geminiError {
      case .missingApiKey:
        return ProviderHealthStatus(state: .error, message: "Missing API key", updatedAt: now)
      case .invalidBaseURL:
        return ProviderHealthStatus(state: .error, message: "Invalid base URL", updatedAt: now)
      case .blocked:
        return ProviderHealthStatus(state: .error, message: "Blocked by provider", updatedAt: now)
      case .requestFailed(let status, _):
        return statusHealth(status: status, updatedAt: now)
      case .emptyResponse, .overRewrite:
        return ProviderHealthStatus(state: .error, message: "Invalid response", updatedAt: now)
      }
    }

    if let openRouterError = error as? OpenRouterCorrector.OpenRouterError {
      switch openRouterError {
      case .missingApiKey:
        return ProviderHealthStatus(state: .error, message: "Missing API key", updatedAt: now)
      case .invalidBaseURL:
        return ProviderHealthStatus(state: .error, message: "Invalid base URL", updatedAt: now)
      case .requestFailed(let status, _):
        if status == 401 || status == 403 {
          return ProviderHealthStatus(state: .error, message: "Unauthorized", updatedAt: now)
        }
        if status == 402 {
          return ProviderHealthStatus(state: .error, message: "Payment required", updatedAt: now)
        }
        if status == 404 {
          return ProviderHealthStatus(state: .error, message: "Model not found", updatedAt: now)
        }
        return statusHealth(status: status, updatedAt: now)
      case .emptyResponse, .overRewrite:
        return ProviderHealthStatus(state: .error, message: "Invalid response", updatedAt: now)
      }
    }

    if let openAIError = error as? OpenAICorrector.OpenAIError {
      switch openAIError {
      case .missingApiKey:
        return ProviderHealthStatus(state: .error, message: "Missing API key", updatedAt: now)
      case .invalidBaseURL:
        return ProviderHealthStatus(state: .error, message: "Invalid base URL", updatedAt: now)
      case .invalidModel:
        return ProviderHealthStatus(state: .error, message: "Invalid model", updatedAt: now)
      case .requestFailed(let status, _):
        if status == 401 || status == 403 {
          return ProviderHealthStatus(state: .error, message: "Unauthorized", updatedAt: now)
        }
        if status == 402 {
          return ProviderHealthStatus(state: .error, message: "Payment required", updatedAt: now)
        }
        if status == 404 {
          return ProviderHealthStatus(state: .error, message: "Model not found", updatedAt: now)
        }
        return statusHealth(status: status, updatedAt: now)
      case .emptyResponse, .overRewrite:
        return ProviderHealthStatus(state: .error, message: "Invalid response", updatedAt: now)
      }
    }

    if let anthropicError = error as? AnthropicCorrector.AnthropicError {
      switch anthropicError {
      case .missingApiKey:
        return ProviderHealthStatus(state: .error, message: "Missing API key", updatedAt: now)
      case .invalidBaseURL:
        return ProviderHealthStatus(state: .error, message: "Invalid base URL", updatedAt: now)
      case .invalidModel:
        return ProviderHealthStatus(state: .error, message: "Invalid model", updatedAt: now)
      case .requestFailed(let status, _):
        if status == 401 || status == 403 {
          return ProviderHealthStatus(state: .error, message: "Unauthorized", updatedAt: now)
        }
        if status == 404 {
          return ProviderHealthStatus(state: .error, message: "Model not found", updatedAt: now)
        }
        return statusHealth(status: status, updatedAt: now)
      case .emptyResponse, .overRewrite:
        return ProviderHealthStatus(state: .error, message: "Invalid response", updatedAt: now)
      }
    }

    if let toneError = error as? ToneAnalysisError {
      switch toneError {
      case .missingApiKey:
        return ProviderHealthStatus(state: .error, message: "Missing API key", updatedAt: now)
      case .invalidBaseURL:
        return ProviderHealthStatus(state: .error, message: "Invalid base URL", updatedAt: now)
      case .invalidModelName:
        return ProviderHealthStatus(state: .error, message: "Invalid model", updatedAt: now)
      case .requestFailed(let status, _):
        return statusHealth(status: status, updatedAt: now)
      case .rateLimited:
        return ProviderHealthStatus(state: .degraded, message: "Rate limited", updatedAt: now)
      case .emptyResponse, .invalidResponse:
        return ProviderHealthStatus(state: .error, message: "Invalid response", updatedAt: now)
      case .textTooShort, .textTooLong:
        return nil
      }
    }

    if error is URLError {
      return ProviderHealthStatus(state: .degraded, message: "Network error", updatedAt: now)
    }

    return nil
  }

  private func statusHealth(status: Int, updatedAt: Date) -> ProviderHealthStatus {
    if status == 429 {
      return ProviderHealthStatus(state: .degraded, message: "Rate limited", updatedAt: updatedAt)
    }
    if (500...599).contains(status) || status <= 0 {
      return ProviderHealthStatus(state: .degraded, message: "Service issue", updatedAt: updatedAt)
    }
    return ProviderHealthStatus(state: .error, message: "Request failed", updatedAt: updatedAt)
  }
}
