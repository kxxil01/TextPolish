import Sparkle
import XCTest

@testable import GrammarCorrection

final class UpdateCheckFeedbackTests: XCTestCase {
  func testNoUpdateErrorShowsUpToDate() {
    let error = NSError(
      domain: SUSparkleErrorDomain,
      code: Int(SUError.noUpdateError.rawValue),
      userInfo: nil
    )

    let feedback = UpdateCheckFeedback.fromSparkleError(error)

    XCTAssertEqual(feedback.kind, .info)
    XCTAssertEqual(feedback.message, "You're up to date.")
  }

  func testInstallationCanceledShowsInfo() {
    let error = NSError(
      domain: SUSparkleErrorDomain,
      code: Int(SUError.installationCanceledError.rawValue),
      userInfo: nil
    )

    let feedback = UpdateCheckFeedback.fromSparkleError(error)

    XCTAssertEqual(feedback.kind, .info)
    XCTAssertEqual(feedback.message, "Update canceled.")
  }

  func testOtherSparkleErrorsShowFailure() {
    let error = NSError(
      domain: SUSparkleErrorDomain,
      code: Int(SUError.downloadError.rawValue),
      userInfo: nil
    )

    let feedback = UpdateCheckFeedback.fromSparkleError(error)

    XCTAssertEqual(feedback.kind, .error)
    XCTAssertEqual(feedback.message, "Update check failed.")
  }

  func testNonSparkleErrorsShowFailure() {
    let error = NSError(
      domain: NSURLErrorDomain,
      code: URLError.cannotFindHost.rawValue,
      userInfo: nil
    )

    let feedback = UpdateCheckFeedback.fromSparkleError(error)

    XCTAssertEqual(feedback.kind, .error)
    XCTAssertEqual(feedback.message, "Update check failed.")
  }
}
