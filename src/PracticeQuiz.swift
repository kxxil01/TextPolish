import Foundation

/// One change to practice: write `before` the way Learn mode corrected it.
struct PracticeItem: Equatable, Sendable {
  let before: String
  let after: String
  let reason: String?
}

/// A short round of practice from the writer's own mistakes: shows the original phrase, checks the typed fix.
struct PracticeQuiz: Equatable, Sendable {
  static let roundSize = 5

  let items: [PracticeItem]
  private(set) var index = 0
  private(set) var score = 0
  private(set) var answered = false

  init(items: [PracticeItem]) {
    self.items = Array(items.prefix(Self.roundSize))
  }

  var current: PracticeItem? {
    items.indices.contains(index) ? items[index] : nil
  }

  var isFinished: Bool {
    index >= items.count
  }

  /// Checks the answer once per question and counts it toward the score.
  mutating func check(_ answer: String) -> Bool {
    guard let current, !answered else { return false }
    answered = true
    let correct = Self.normalized(answer) == Self.normalized(current.after)
    if correct { score += 1 }
    return correct
  }

  mutating func next() {
    guard answered else { return }
    index += 1
    answered = false
  }

  /// Case, spacing, quotes, and final punctuation do not count against an answer.
  static func normalized(_ text: String) -> String {
    let unified = text.lowercased()
      .replacingOccurrences(of: "\u{2019}", with: "'")
      .replacingOccurrences(of: "\u{2018}", with: "'")
    let words = unified.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return words.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{201C}\u{201D}.,!? "))
  }
}

extension LessonHistory {
  /// Practice from repeated mistakes first, then the most recent other changes, each once and short enough to type.
  func practiceItems(limit: Int = PracticeQuiz.roundSize) -> [PracticeItem] {
    var seen = Set<String>()
    var items: [PracticeItem] = []
    let recent = lessons.flatMap(\.lines).compactMap { RepeatedMistake(line: $0, at: Date()) }
    for mistake in repeatedMistakes(limit: limit) + recent where mistake.after.count <= 60 {
      guard seen.insert(mistake.key).inserted else { continue }
      items.append(PracticeItem(before: mistake.before, after: mistake.after, reason: mistake.reason))
      if items.count == limit { break }
    }
    return items
  }
}
