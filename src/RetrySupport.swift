import Foundation

struct RetryPolicy: Sendable {
  let maxNetworkAttempts: Int
  let maxBackoffSeconds: Double
  let maxRateLimitBackoffSeconds: Double

  init(maxNetworkAttempts: Int = 3, maxBackoffSeconds: Double = 10, maxRateLimitBackoffSeconds: Double = 12) {
    self.maxNetworkAttempts = max(1, maxNetworkAttempts)
    self.maxBackoffSeconds = max(1, maxBackoffSeconds)
    self.maxRateLimitBackoffSeconds = max(1, maxRateLimitBackoffSeconds)
  }

  func retryDelaySeconds(attempt: Int) -> Double {
    min(pow(2.0, Double(max(0, attempt))), maxBackoffSeconds)
  }

  func clampedRateLimitBackoff(_ requested: Double) -> Double {
    let sanitized = requested.isFinite ? requested : 1
    return min(max(1, sanitized), maxRateLimitBackoffSeconds)
  }


  func performWithBackoff<Result>(
    maxAttempts: Int? = nil,
    onRetry: (() -> Void)? = nil,
    operation: (Int, Bool) async throws -> RetryDecision<Result>
  ) async throws -> Result {
    let attemptCount = max(1, maxAttempts ?? maxNetworkAttempts)
    var lastError: Error?

    for attempt in 0..<attemptCount {
      let isLastAttempt = attempt == attemptCount - 1
      switch try await operation(attempt, isLastAttempt) {
      case .success(let value):
        return value
      case .retry(let delay, let error):
        lastError = error
        if isLastAttempt {
          throw error
        }
        onRetry?()
        try await Task.sleep(for: .seconds(delay))
      case .fail(let error):
        throw error
      }
    }

    throw lastError ?? RetryPolicyError.exhaustedWithoutError
  }
}

enum RetryDecision<Result> {
  case success(Result)
  case retry(after: Double, lastError: Error)
  case fail(Error)
}

enum RetryPolicyError: Error {
  case exhaustedWithoutError
}

enum RetryAfterParser {
  static func retryAfterSeconds(from response: HTTPURLResponse, data: Data) -> Double? {
    if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
       !header.isEmpty {
      return parseRetryAfterValue(header) ?? 5
    }
    return extractRetryAfter(from: data)
  }

  static func extractRetryAfter(from data: Data) -> Double? {
    guard let string = String(data: data, encoding: .utf8) else { return nil }
    guard let range = string.range(of: #""retry_after"\s*:\s*"?([^",}\s]+)"?"#, options: .regularExpression) else {
      return nil
    }

    let match = String(string[range])
    let rawValue = match
      .replacingOccurrences(of: #"^\s*"retry_after"\s*:\s*"?#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #""?$"#, with: "", options: .regularExpression)

    return parseRetryAfterValue(rawValue) ?? 5
  }

  private static func parseRetryAfterValue(_ rawValue: String) -> Double? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if let seconds = Int(value) {
      return Double(max(0, seconds))
    }

    if let seconds = Double(value) {
      return Double(max(0, Int(seconds)))
    }

    if let date = parseHTTPDate(value) {
      return max(0, ceil(date.timeIntervalSinceNow))
    }

    return nil
  }

  private static func parseHTTPDate(_ value: String) -> Date? {
    let formatters: [DateFormatter] = [
      makeHTTPDateFormatter("EEE',' dd MMM yyyy HH':'mm':'ss zzz"),
      makeHTTPDateFormatter("EEEE',' dd-MMM-yy HH':'mm':'ss zzz"),
      makeHTTPDateFormatter("EEE MMM d HH':'mm':'ss yyyy"),
    ]

    for formatter in formatters {
      if let date = formatter.date(from: value) {
        return date
      }
    }
    return nil
  }

  private static func makeHTTPDateFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
  }
}

enum ErrorLogSanitizer {
  static func sanitize(_ raw: String?, maxLength: Int = 200) -> String? {
    guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      return nil
    }

    text = replacing(#"(?i)(bearer\s+)[A-Za-z0-9._\-]{8,}"#, in: text, template: "$1[REDACTED]")
    text = replacing(#"(?i)\bsk-ant-[A-Za-z0-9_\-]{8,}\b"#, in: text, template: "sk-ant-[REDACTED]")
    text = replacing(#"(?i)\bsk-[A-Za-z0-9_\-]{8,}\b"#, in: text, template: "sk-[REDACTED]")
    text = replacing(#"(?i)(\"?(api[_-]?key|authorization|x-api-key)\"?\s*[:=]\s*\"?)[^\",\s]{6,}"#, in: text, template: "$1[REDACTED]")

    if text.count > maxLength {
      return String(text.prefix(maxLength)) + "…"
    }
    return text
  }

  private static func replacing(_ pattern: String, in source: String, template: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return regex.stringByReplacingMatches(in: source, options: [], range: range, withTemplate: template)
  }
}
