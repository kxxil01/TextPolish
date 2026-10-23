import XCTest

@testable import GrammarCorrection

/// `TextPolish polish` and `TextPolish translate` for scripts and the Shortcuts app.
final class CommandLinePolishTests: XCTestCase {
  func testParsesCommandsStylesAndText() throws {
    XCTAssertEqual(try CommandLinePolish.parse(["polish", "pls", "check"]), .run(.polish, style: nil, text: "pls check"))
    XCTAssertEqual(try CommandLinePolish.parse(["polish", "--style", "formal"]), .run(.polish, style: "formal", text: nil))
    XCTAssertEqual(
      try CommandLinePolish.parse(["polish", "-s", "Status", "--", "--style"]), .run(.polish, style: "Status", text: "--style")
    )
    XCTAssertEqual(try CommandLinePolish.parse(["translate", "tolong", "cek"]), .run(.translate, style: nil, text: "tolong cek"))
    XCTAssertEqual(try CommandLinePolish.parse(["--help"]), .help)
  }

  func testOtherArgumentsLaunchTheAppAsUsual() throws {
    XCTAssertNil(try CommandLinePolish.parse([]))
    XCTAssertNil(try CommandLinePolish.parse(["-NSDocumentRevisionsDebugMode", "YES"]))
    XCTAssertNil(try CommandLinePolish.parse(["--unregister-login-item"]))
  }

  func testRejectsMissingStyleNamesAndStylesOnTranslate() {
    XCTAssertThrowsError(try CommandLinePolish.parse(["polish", "--style"])) { error in
      XCTAssertEqual(error as? CommandLinePolish.Failure, .usage("--style needs a style name."))
    }
    XCTAssertThrowsError(try CommandLinePolish.parse(["translate", "--style", "formal", "hi"]))
  }

  func testStyleNamesMapToCorrectionStyles() throws {
    var settings = Settings()
    settings.polishStyle = .shorter
    settings.customStyles["custom"] = Settings.CustomStyle(name: "Status", instruction: "bullet points")
    settings.normalizeRuntimeValues()

    XCTAssertEqual(try CommandLinePolish.correctionStyle(named: nil, action: .polish, settings: settings), .shorten)
    XCTAssertEqual(try CommandLinePolish.correctionStyle(named: "Formal", action: .polish, settings: settings), .formal)
    XCTAssertEqual(try CommandLinePolish.correctionStyle(named: "status", action: .polish, settings: settings), .custom("bullet points"))
    XCTAssertEqual(try CommandLinePolish.correctionStyle(named: nil, action: .translate, settings: settings), .translateToEnglish)
    XCTAssertThrowsError(try CommandLinePolish.correctionStyle(named: "custom", action: .polish, settings: Settings())) { error in
      XCTAssertEqual(error as? CommandLinePolish.Failure, .unknownStyle("custom"), "Custom needs an instruction first")
    }
  }

  @MainActor
  func testNonCommandsReturnNilAndHelpSucceeds() {
    XCTAssertNil(CommandLinePolish.runIfRequested([]))
    XCTAssertEqual(CommandLinePolish.runIfRequested(["help"]), 0)
    XCTAssertEqual(CommandLinePolish.runIfRequested(["polish", "--style", "bogus", "hi"]), 2)
  }

  func testWaitsForTheCorrectionAndPassesErrorsThrough() throws {
    XCTAssertEqual(
      try CommandLinePolish.waitForCorrection(corrector: CommandLineStubCorrector(), text: "hello", style: .formal),
      "hello (formal)"
    )
    XCTAssertThrowsError(
      try CommandLinePolish.waitForCorrection(corrector: CommandLineStubCorrector(), text: "fail", style: .formal)
    )
  }
}

private struct CommandLineStubCorrector: GrammarCorrector {
  struct Failure: Error {}

  func correct(_ text: String) async throws -> String {
    try await correct(text, style: .minimal)
  }

  func correct(_ text: String, style: CorrectionStyle) async throws -> String {
    if text == "fail" {
      throw Failure()
    }
    return "\(text) (\(style))"
  }
}
