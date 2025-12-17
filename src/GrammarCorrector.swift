protocol GrammarCorrector {
  @MainActor func correct(_ text: String) async throws -> String
}
