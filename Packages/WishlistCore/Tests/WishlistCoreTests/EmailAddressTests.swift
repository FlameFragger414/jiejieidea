import Foundation
import XCTest

@testable import WishlistCore

final class EmailAddressTests: XCTestCase {
  func testTrimsAndLowercasesValidAddress() throws {
    let address = try EmailAddress("  Mia.Chen+Gifts@Example.INVALID \n")
    XCTAssertEqual(address.normalized, "mia.chen+gifts@example.invalid")
    XCTAssertEqual(address.domain, "example.invalid")
  }

  func testRejectsMissingLocalPartOrDomain() {
    XCTAssertFalse(EmailAddress.isValid("@example.invalid"))
    XCTAssertFalse(EmailAddress.isValid("mia@"))
    XCTAssertFalse(EmailAddress.isValid("mia.example.invalid"))
  }

  func testRejectsMultipleAtSigns() {
    XCTAssertFalse(EmailAddress.isValid("mia@chen@example.invalid"))
  }

  func testRejectsWhitespaceInsideAddress() {
    XCTAssertFalse(EmailAddress.isValid("mia chen@example.invalid"))
    XCTAssertFalse(EmailAddress.isValid("mia@exa mple.invalid"))
  }

  func testRejectsDotEdgeCasesInLocalPart() {
    XCTAssertFalse(EmailAddress.isValid(".mia@example.invalid"))
    XCTAssertFalse(EmailAddress.isValid("mia.@example.invalid"))
    XCTAssertFalse(EmailAddress.isValid("mia..chen@example.invalid"))
  }

  func testRejectsDomainWithoutDotOrWithHyphenEdges() {
    XCTAssertFalse(EmailAddress.isValid("mia@localhost"))
    XCTAssertFalse(EmailAddress.isValid("mia@-example.invalid"))
    XCTAssertFalse(EmailAddress.isValid("mia@example-.invalid"))
  }

  func testRejectsNumericOrSingleCharacterTopLevelDomain() {
    XCTAssertFalse(EmailAddress.isValid("mia@example.12"))
    XCTAssertFalse(EmailAddress.isValid("mia@example.i"))
  }

  func testRejectsNonASCIIAndControlCharacters() {
    XCTAssertFalse(EmailAddress.isValid("miä@example.invalid"))
    XCTAssertFalse(EmailAddress.isValid("mia\u{0007}@example.invalid"))
  }

  func testRejectsOverlongLocalPart() {
    let longLocalPart = String(repeating: "a", count: 65)
    XCTAssertFalse(EmailAddress.isValid("\(longLocalPart)@example.invalid"))
  }

  func testThrowsFieldScopedValidationIssue() {
    do {
      _ = try EmailAddress("not-an-address")
      XCTFail("Expected a validation issue")
    } catch let issue as ValidationIssue {
      XCTAssertEqual(issue.field, "email")
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }
}
