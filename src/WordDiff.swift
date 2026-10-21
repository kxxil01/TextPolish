import AppKit

/// Word-level differences between the original and polished text, for showing what Polish changed.
enum WordDiff {
  enum Change: Equatable {
    case same(String)
    case removed(String)
    case added(String)
  }

  /// Above this many token pairs the comparison gets slow, so the whole text shows as replaced.
  private static let maxComparisonCells = 4_000_000

  static func changes(from original: String, to polished: String) -> [Change] {
    let old = tokens(in: original)
    let new = tokens(in: polished)
    guard old.count * new.count <= maxComparisonCells else {
      return merged([.removed(original), .added(polished)])
    }

    // Longest common subsequence table, filled from the end so the walk below goes forward.
    var lengths = Array(repeating: Array(repeating: 0, count: new.count + 1), count: old.count + 1)
    for i in stride(from: old.count - 1, through: 0, by: -1) {
      for j in stride(from: new.count - 1, through: 0, by: -1) {
        lengths[i][j] = old[i] == new[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
      }
    }

    var result: [Change] = []
    var i = 0
    var j = 0
    while i < old.count, j < new.count {
      if old[i] == new[j] {
        result.append(.same(old[i]))
        i += 1
        j += 1
      } else if lengths[i + 1][j] >= lengths[i][j + 1] {
        result.append(.removed(old[i]))
        i += 1
      } else {
        result.append(.added(new[j]))
        j += 1
      }
    }
    result += old[i...].map(Change.removed) + new[j...].map(Change.added)
    return merged(grouped(result))
  }

  /// Removed text struck through on red, added text on green, the rest plain. A space separates a removed
  /// phrase from its replacement so the two do not run together.
  static func attributedString(from changes: [Change], font: NSFont) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (index, change) in changes.enumerated() {
      if case .added(let value) = change, index > 0, case .removed(let previous) = changes[index - 1],
         previous.last?.isWhitespace == false, value.first?.isWhitespace == false
      {
        result.append(NSAttributedString(string: " ", attributes: [.font: font]))
      }
      var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
      let text: String
      switch change {
      case .same(let value):
        text = value
      case .removed(let value):
        text = value
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        attributes[.foregroundColor] = NSColor.systemRed
        attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.12)
      case .added(let value):
        text = value
        attributes[.foregroundColor] = NSColor.systemGreen
        attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.15)
      }
      result.append(NSAttributedString(string: text, attributes: attributes))
    }
    return result
  }

  /// Words (letters, digits, apostrophes), runs of whitespace, and single punctuation marks.
  static func tokens(in text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var currentKind: Character.Kind?
    for character in text {
      let kind = Character.Kind(character)
      if kind == currentKind, kind != .punctuation {
        current.append(character)
      } else {
        if !current.isEmpty { tokens.append(current) }
        current = String(character)
        currentKind = kind
      }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
  }

  /// Folds the spaces between nearby edits into them, so a reworded phrase shows as one removed phrase and
  /// its replacement instead of alternating single words. Line breaks end a phrase.
  private static func grouped(_ changes: [Change]) -> [Change] {
    var result: [Change] = []
    var region: [Change] = []
    var heldSpaces: [Change] = []

    func flushRegion() {
      let hasRemoved = region.contains { if case .removed = $0 { return true } else { return false } }
      let hasAdded = region.contains { if case .added = $0 { return true } else { return false } }
      guard hasRemoved, hasAdded else {
        result += region
        region = []
        return
      }
      var oldText = ""
      var newText = ""
      for change in region {
        switch change {
        case .same(let text):
          oldText += text
          newText += text
        case .removed(let text):
          oldText += text
        case .added(let text):
          newText += text
        }
      }
      result += [.removed(oldText), .added(newText)]
      region = []
    }

    for change in changes {
      guard case .same(let text) = change else {
        region += heldSpaces
        heldSpaces = []
        region.append(change)
        continue
      }
      if !region.isEmpty, text.allSatisfy(\.isWhitespace), !text.contains(where: \.isNewline) {
        heldSpaces.append(change)
      } else {
        flushRegion()
        result += heldSpaces + [change]
        heldSpaces = []
      }
    }
    flushRegion()
    return result + heldSpaces
  }

  /// Joins neighbouring changes of the same kind so the view shows phrases, not single words.
  private static func merged(_ changes: [Change]) -> [Change] {
    var result: [Change] = []
    for change in changes {
      switch (result.last, change) {
      case let (.same(previous)?, .same(next)):
        result[result.count - 1] = .same(previous + next)
      case let (.removed(previous)?, .removed(next)):
        result[result.count - 1] = .removed(previous + next)
      case let (.added(previous)?, .added(next)):
        result[result.count - 1] = .added(previous + next)
      default:
        result.append(change)
      }
    }
    return result
  }
}

private extension Character {
  enum Kind {
    case word
    case space
    case punctuation
  }
}

private extension Character.Kind {
  init(_ character: Character) {
    if character.isLetter || character.isNumber || character == "'" || character == "’" {
      self = .word
    } else if character.isWhitespace {
      self = .space
    } else {
      self = .punctuation
    }
  }
}
