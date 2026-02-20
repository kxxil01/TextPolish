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
}

enum RetryAfterParser {
  static func retryAfterSeconds(from response: HTTPURLResponse, data: Data) -> Double? {
    if let header = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
       let value = Double(header) {
      return value
    }
    return extractRetryAfter(from: data)
  }

  static func extractRetryAfter(from data: Data) -> Double? {
    guard let string = String(data: data, encoding: .utf8) else { return nil }
    guard let range = string.range(of: #""retry_after"\s*:\s*"?(\d+)"?"#, options: .regularExpression) else {
      return nil
    }
    let match = string[range]
    let numberString = match.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
    guard let number = Int(numberString) else { return nil }
    return Double(number)
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
