import Foundation

/// A system + user message pair for AI prompts.
/// System carries instructions; user carries only the text to process.
struct PromptPair: Sendable {
  let system: String
  let user: String
}
