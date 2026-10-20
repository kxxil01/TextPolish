import XCTest

@testable import GrammarCorrection

final class KeychainExistenceTests: XCTestCase {
  private let service = "com.kxxil01.TextPolish.Tests.existence"
  private let account = "openAIApiKey"

  override func setUp() {
    super.setUp()
    try? Keychain.deletePassword(service: service, account: account)
  }

  override func tearDown() {
    try? Keychain.deletePassword(service: service, account: account)
    super.tearDown()
  }

  func testDetectsStoredKeyWithoutReadingIt() throws {
    XCTAssertFalse(Keychain.hasConfiguredPassword(primaryService: service, account: account))

    try Keychain.setPassword("sk-test", service: service, account: account)

    XCTAssertTrue(Keychain.hasConfiguredPassword(primaryService: service, account: account))
  }

  func testReportsMissingKeyAfterDelete() throws {
    try Keychain.setPassword("sk-test", service: service, account: account)
    try Keychain.deletePassword(service: service, account: account)

    XCTAssertFalse(Keychain.hasConfiguredPassword(primaryService: service, account: account))
  }
}
