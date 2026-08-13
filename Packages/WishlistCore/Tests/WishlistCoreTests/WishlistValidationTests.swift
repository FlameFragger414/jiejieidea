import Foundation
import XCTest

@testable import WishlistCore

final class WishlistValidationTests: XCTestCase {
  func testBlankNameIsRejected() {
    let draft = WishlistDraft(name: "  \n ")
    XCTAssertEqual(draft.validationIssues().first?.field, "name")
  }

  func testNameIsTrimmed() {
    let draft = WishlistDraft(name: "  Birthday weekend  ")
    XCTAssertEqual(draft.normalizedName, "Birthday weekend")
  }

  func testPastEventDateIsRejected() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 2_000_000)
    let draft = WishlistDraft(name: "Birthday", eventDate: now.addingTimeInterval(-86_400))
    XCTAssertTrue(
      draft.validationIssues(calendar: calendar, now: now).contains { $0.field == "eventDate" })
  }

  func testTodayIsAccepted() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 2_000_000)
    let draft = WishlistDraft(name: "Birthday", eventDate: now.addingTimeInterval(-60))
    XCTAssertFalse(
      draft.validationIssues(calendar: calendar, now: now).contains { $0.field == "eventDate" })
  }

  func testWishlistTypeMatchesDatabaseValue() throws {
    let encoded = try JSONEncoder().encode(WishlistType.babyShower)
    XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"baby_shower\"")
  }
}
