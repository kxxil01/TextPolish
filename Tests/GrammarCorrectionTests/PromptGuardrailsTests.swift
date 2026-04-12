import XCTest

@testable import GrammarCorrection

final class PromptGuardrailsTests: XCTestCase {

  // MARK: - sanitizeExtraInstruction

  func testSanitizeStripsControlCharacters() {
    let input = "Fix grammar\u{0000}\u{0007}\u{001B}[31m nicely"
    let result = PromptGuardrails.sanitizeExtraInstruction(input)
    XCTAssertNotNil(result)
    XCTAssertFalse(result!.contains("\u{0000}"))
    XCTAssertFalse(result!.contains("\u{0007}"))
    XCTAssertFalse(result!.contains("\u{001B}"))
    XCTAssertTrue(result!.contains("Fix grammar"))
    XCTAssertTrue(result!.contains("nicely"))
  }

  func testSanitizeTruncatesLongInstruction() {
    let input = String(repeating: "a", count: 600)
    let result = PromptGuardrails.sanitizeExtraInstruction(input)
    XCTAssertNotNil(result)
    XCTAssertLessThanOrEqual(result!.count, 500)
  }

  func testSanitizeTrimsWhitespace() {
    let result = PromptGuardrails.sanitizeExtraInstruction("  hello  ")
    XCTAssertEqual(result, "hello")
  }

  func testSanitizeReturnsNilForEmpty() {
    XCTAssertNil(PromptGuardrails.sanitizeExtraInstruction(""))
    XCTAssertNil(PromptGuardrails.sanitizeExtraInstruction("   "))
  }

  func testSanitizeReturnsNilForNilInput() {
    XCTAssertNil(PromptGuardrails.sanitizeExtraInstruction(nil))
  }

  // MARK: - validateInputLength

  func testValidateInputAcceptsNormalText() {
    let text = "Hello world, this is a normal sentence."
    XCTAssertNoThrow(try PromptGuardrails.validateInputLength(text, maxLength: 10_000))
  }

  func testValidateInputRejectsEmptyText() {
    XCTAssertThrowsError(try PromptGuardrails.validateInputLength("", maxLength: 10_000)) { error in
      XCTAssertEqual(error as? PromptGuardrails.GuardrailError, .textEmpty)
    }
  }

  func testValidateInputRejectsWhitespaceOnly() {
    XCTAssertThrowsError(try PromptGuardrails.validateInputLength("   \n  ", maxLength: 10_000)) { error in
      XCTAssertEqual(error as? PromptGuardrails.GuardrailError, .textEmpty)
    }
  }

  func testValidateInputRejectsTooLongText() {
    let text = String(repeating: "x", count: 10_001)
    XCTAssertThrowsError(try PromptGuardrails.validateInputLength(text, maxLength: 10_000)) { error in
      XCTAssertEqual(error as? PromptGuardrails.GuardrailError, .textTooLong)
    }
  }

  // MARK: - detectRefusal

  func testDetectRefusalCatchesCommonPatterns() {
    let refusals = [
      "I can't modify this text as it contains harmful content.",
      "As an AI language model, I cannot process this request.",
      "I'm sorry, but I can't assist with that.",
      "I apologize, but I'm unable to correct this text.",
    ]

    for text in refusals {
      XCTAssertTrue(
        PromptGuardrails.detectRefusal(text),
        "Should detect refusal in: \(text)"
      )
    }
  }

  func testDetectRefusalAllowsNormalText() {
    let normal = [
      "I can't believe how great this turned out.",
      "As an AI researcher, she published many papers.",
      "I'm sorry to hear about your loss.",
      "The model is working as expected.",
    ]

    for text in normal {
      XCTAssertFalse(
        PromptGuardrails.detectRefusal(text),
        "Should not flag normal text: \(text)"
      )
    }
  }

  // MARK: - validateOutputLength

  func testOutputLengthAcceptsReasonableCorrection() {
    let input = "Hello wrold"
    let output = "Hello world"
    XCTAssertTrue(PromptGuardrails.validateOutputLength(input: input, output: output))
  }

  func testOutputLengthRejectsExcessivelyLongOutput() {
    let input = "Short text."
    let output = String(repeating: "This is way too long. ", count: 100)
    XCTAssertFalse(PromptGuardrails.validateOutputLength(input: input, output: output))
  }

  func testOutputLengthAcceptsEmptyForEmpty() {
    XCTAssertTrue(PromptGuardrails.validateOutputLength(input: "", output: ""))
  }
}
