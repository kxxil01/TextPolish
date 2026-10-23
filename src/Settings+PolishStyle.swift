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
    /// The writer's own styles, set in Settings > Advanced.
    case custom
    case custom2
    case custom3

    /// The slots for the writer's own styles.
    static let customSlots: [PolishStyle] = [.custom, .custom2, .custom3]

    var isCustom: Bool {
      Self.customSlots.contains(self)
    }

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
      case .custom, .custom2, .custom3: return .clarify
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
      case .custom2: return "Custom 2"
      case .custom3: return "Custom 3"
      }
    }
  }
}

// MARK: - Styles per app and Custom

extension Settings {
  func styleHotKey(for style: PolishStyle) -> HotKey? {
    styleHotKeys[style.rawValue]
  }

  /// A Custom slot's name and instruction; an unused slot has its default name and no instruction.
  func customStyle(_ slot: PolishStyle) -> CustomStyle {
    customStyles[slot.rawValue] ?? CustomStyle(name: slot.displayName)
  }

  /// The styles to offer: every built-in style, and each Custom style once it has an instruction.
  var availablePolishStyles: [PolishStyle] {
    PolishStyle.allCases.filter { !$0.isCustom || customStyle($0).instruction != nil }
  }

  /// What Polish sends for a style: a Custom style carries the writer's instruction.
  func correctionStyle(for style: PolishStyle) -> CorrectionStyle {
    if style.isCustom, let instruction = customStyle(style).instruction {
      return .custom(instruction)
    }
    return style.correctionStyle
  }

  /// Whether Polish in `style` translates text that is mostly Indonesian. Minimal, used in terminals and code
  /// editors, never does, and neither does a writer who chose Indonesian as the correction language.
  func translatesIndonesian(in style: CorrectionStyle) -> Bool {
    autoTranslateIndonesian && correctionLanguage != .indonesian && style.rewritesWording && !style.translatesToEnglish
  }

  /// A style's name in menus and Settings; a Custom style uses the name the writer gave it.
  func displayName(for style: PolishStyle) -> String {
    style.isCustom ? customStyle(style).name : style.displayName
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

// MARK: - Custom styles

extension Settings {
  /// One of the writer's own styles: its name in menus and how it should sound.
  struct CustomStyle: Codable, Equatable, Sendable {
    var name: String
    var instruction: String?
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
