import Foundation

/// The message the user last explained, kept briefly so Reply in English can answer it.
/// It stays in memory only and is forgotten after `lifetime`.
struct ReplyContext {
  static let lifetime: TimeInterval = 15 * 60

  private var message: String?
  private var rememberedAt: Date?

  mutating func remember(_ message: String, at date: Date = Date()) {
    self.message = message
    rememberedAt = date
  }

  /// The remembered message while it is recent, else nil.
  func recentMessage(now: Date = Date()) -> String? {
    guard let message, let rememberedAt, now.timeIntervalSince(rememberedAt) <= Self.lifetime else { return nil }
    return message
  }
}
