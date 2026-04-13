import Foundation

enum GeminiEndpointPath {
  private static let versionSegments: Set<String> = ["v1", "v1beta"]

  static func modelsPath(basePath: String, apiVersion: String) -> String {
    let prefix = normalizedPrefixPath(basePath)
    return appendedPath(prefix: prefix, suffixSegments: [apiVersion, "models"])
  }

  static func generateContentPath(basePath: String, apiVersion: String, model: String) -> String {
    let prefix = normalizedPrefixPath(basePath)
    return appendedPath(prefix: prefix, suffixSegments: [apiVersion, "models", "\(model):generateContent"])
  }

  private static func normalizedPrefixPath(_ basePath: String) -> String {
    var segments = basePath
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    if segments.last?.lowercased() == "models" {
      segments.removeLast()
    }

    if let last = segments.last, versionSegments.contains(last.lowercased()) {
      segments.removeLast()
    }

    guard !segments.isEmpty else { return "" }
    return "/" + segments.joined(separator: "/")
  }

  private static func appendedPath(prefix: String, suffixSegments: [String]) -> String {
    let normalizedSuffix = suffixSegments
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
      .filter { !$0.isEmpty }
      .joined(separator: "/")

    if prefix.isEmpty {
      return normalizedSuffix.isEmpty ? "/" : "/" + normalizedSuffix
    }
    guard !normalizedSuffix.isEmpty else { return prefix }
    return prefix + "/" + normalizedSuffix
  }
}

enum OpenAIEndpointPath {
  static func modelsPath(basePath: String) -> String {
    let prefix = normalizedPrefixPath(basePath)
    return appendedPath(prefix: prefix, suffixSegments: ["models"])
  }

  static func chatCompletionsPath(basePath: String) -> String {
    let prefix = normalizedPrefixPath(basePath)
    return appendedPath(prefix: prefix, suffixSegments: ["chat", "completions"])
  }

  private static func normalizedPrefixPath(_ basePath: String) -> String {
    var segments = basePath
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    if segments.last?.lowercased() == "models" {
      segments.removeLast()
    } else if segments.count >= 2,
              segments[segments.count - 2].lowercased() == "chat",
              segments.last?.lowercased() == "completions"
    {
      segments.removeLast(2)
    }

    guard !segments.isEmpty else { return "" }
    return "/" + segments.joined(separator: "/")
  }

  private static func appendedPath(prefix: String, suffixSegments: [String]) -> String {
    let normalizedSuffix = suffixSegments
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
      .filter { !$0.isEmpty }
      .joined(separator: "/")

    if prefix.isEmpty {
      return normalizedSuffix.isEmpty ? "/" : "/" + normalizedSuffix
    }
    guard !normalizedSuffix.isEmpty else { return prefix }
    return prefix + "/" + normalizedSuffix
  }
}

enum AnthropicEndpointPath {
  static func modelsPath(basePath: String) -> String {
    let prefix = normalizedPrefixPath(basePath)
    return appendedPath(prefix: prefix, suffixSegments: ["v1", "models"])
  }

  private static func normalizedPrefixPath(_ basePath: String) -> String {
    var segments = basePath
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    if segments.last?.lowercased() == "models" {
      segments.removeLast()
    }
    if let last = segments.last, last.lowercased() == "v1" {
      segments.removeLast()
    }

    guard !segments.isEmpty else { return "" }
    return "/" + segments.joined(separator: "/")
  }

  private static func appendedPath(prefix: String, suffixSegments: [String]) -> String {
    let normalizedSuffix = suffixSegments
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
      .filter { !$0.isEmpty }
      .joined(separator: "/")

    if prefix.isEmpty {
      return normalizedSuffix.isEmpty ? "/" : "/" + normalizedSuffix
    }
    guard !normalizedSuffix.isEmpty else { return prefix }
    return prefix + "/" + normalizedSuffix
  }
}

enum OpenRouterEndpointPath {
  static func modelsPath(basePath: String) -> String {
    let prefix = normalizedPrefixPath(basePath)
    return appendedPath(prefix: prefix, suffixSegments: ["models"])
  }

  static func chatCompletionsPath(basePath: String) -> String {
    let prefix = normalizedPrefixPath(basePath)
    return appendedPath(prefix: prefix, suffixSegments: ["chat", "completions"])
  }

  private static func normalizedPrefixPath(_ basePath: String) -> String {
    var segments = basePath
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    if segments.last?.lowercased() == "models" {
      segments.removeLast()
    } else if segments.count >= 2,
              segments[segments.count - 2].lowercased() == "chat",
              segments.last?.lowercased() == "completions"
    {
      segments.removeLast(2)
    }

    guard !segments.isEmpty else { return "" }
    return "/" + segments.joined(separator: "/")
  }

  private static func appendedPath(prefix: String, suffixSegments: [String]) -> String {
    let normalizedSuffix = suffixSegments
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
      .filter { !$0.isEmpty }
      .joined(separator: "/")

    if prefix.isEmpty {
      return normalizedSuffix.isEmpty ? "/" : "/" + normalizedSuffix
    }
    guard !normalizedSuffix.isEmpty else { return prefix }
    return prefix + "/" + normalizedSuffix
  }
}
