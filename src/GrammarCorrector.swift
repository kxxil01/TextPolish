protocol GrammarCorrector: Sendable {
  func correct(_ text: String) async throws -> String
}
