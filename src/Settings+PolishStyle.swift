import Foundation

extension Settings {
  /// How far Polish may change text.
  enum PolishStyle: String, Codable, Sendable, CaseIterable {
    /// Improve wording so it reads naturally, and join choppy line breaks.
    case natural
    /// Fix typos, grammar, and clear punctuation mistakes only.
    case minimal
    /// Cut filler and repetition, keeping every fact and request.
    case shorter
    /// Polite and professional, for work email or clients.
    case formal
    /// Warm and casual, for chat with coworkers.
    case friendly
    /// The writer's own style, set in Settings > Advanced.
    case custom

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      self = PolishStyle(rawValue: try container.decode(String.self)) ?? .natural
    }

    var correctionStyle: CorrectionStyle {
      switch self {
      case .natural: return .clarify
      case .minimal: return .minimal
      case .shorter: return .shorten
      case .formal: return .formal
      case .friendly: return .friendly
      // Without the writer's instruction, Custom polishes like Natural; `Settings.correctionStyle(for:)` adds it.
      case .custom: return .clarify
      }
    }

    var displayName: String {
      switch self {
      case .natural: return "Natural"
      case .minimal: return "Minimal"
      case .shorter: return "Shorter"
      case .formal: return "Formal"
      case .friendly: return "Friendly"
      case .custom: return "Custom"
      }
    }
  }
}

// MARK: - Styles per app and Custom

extension Settings {
  func styleHotKey(for style: PolishStyle) -> HotKey? {
    styleHotKeys[style.rawValue]
  }

  /// Whether the Custom style has an instruction, so menus and Settings offer it.
  var hasCustomStyle: Bool {
    customStyleInstruction != nil
  }

  /// The styles to offer: every built-in style, and Custom once it has an instruction.
  var availablePolishStyles: [PolishStyle] {
    PolishStyle.allCases.filter { $0 != .custom || hasCustomStyle }
  }

  /// What Polish sends for a style: Custom carries the writer's instruction.
  func correctionStyle(for style: PolishStyle) -> CorrectionStyle {
    if style == .custom, let customStyleInstruction {
      return .custom(customStyleInstruction)
    }
    return style.correctionStyle
  }

  /// A style's name in menus and Settings; Custom uses the name the writer gave it.
  func displayName(for style: PolishStyle) -> String {
    style == .custom ? customStyleName : style.displayName
  }

  /// The style Polish uses in an app: the user's choice for it, then the built-in default, then the default style.
  func polishStyle(forApp bundleIdentifier: String?) -> PolishStyle {
    guard let bundleIdentifier else { return polishStyle }
    return appPolishStyles[bundleIdentifier] ?? defaultPolishStyle(forApp: bundleIdentifier)
  }

  /// The style an app gets when the user has not chosen one for it.
  func defaultPolishStyle(forApp bundleIdentifier: String) -> PolishStyle {
    Self.prefersMinimalStyle(bundleIdentifier) ? .minimal : polishStyle
  }

  /// Terminals and code editors hold commands and code, where rewording does more harm than good.
  private static let minimalStyleApps: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
    "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "com.apple.dt.Xcode",
    "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    "com.sublimetext.4", "com.panic.Nova",
  ]

  private static func prefersMinimalStyle(_ bundleIdentifier: String) -> Bool {
    minimalStyleApps.contains(bundleIdentifier) || bundleIdentifier.hasPrefix("com.jetbrains.")
  }
}

// MARK: - Explain Message

extension Settings {
  /// The language Explain Message writes in.
  enum ExplanationLanguage: String, Codable, Sendable, CaseIterable {
    case indonesian
    case simpleEnglish

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      self = ExplanationLanguage(rawValue: try container.decode(String.self)) ?? .indonesian
    }

    var displayName: String {
      switch self {
      case .indonesian: return "Indonesian"
      case .simpleEnglish: return "Simple English"
      }
    }

    var promptName: String {
      switch self {
      case .indonesian: return "Indonesian"
      case .simpleEnglish: return "simple, plain English"
      }
    }
  }
}
