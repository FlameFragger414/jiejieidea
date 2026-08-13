import Foundation
import XCTest

@testable import WishlistCore

final class WishlistItemValidationTests: XCTestCase {
  func testBlankProductNameIsRejected() {
    XCTAssertEqual(WishlistItemDraft().validationIssues().first?.field, "productName")
  }

  func testQuantityBoundsAreValidated() {
    var draft = WishlistItemDraft(productName: "Camera")
    draft.desiredQuantity = 0
    XCTAssertTrue(draft.validationIssues().contains { $0.field == "desiredQuantity" })

    draft.desiredQuantity = 1_000
    XCTAssertTrue(draft.validationIssues().contains { $0.field == "desiredQuantity" })
  }

  func testOnlyHTTPProductURLsAreAccepted() {
    let invalid = WishlistItemDraft(
      productName: "Camera", productURLText: "file:///private/photo.jpg")
    XCTAssertTrue(invalid.validationIssues().contains { $0.field == "productURL" })

    let valid = WishlistItemDraft(
      productName: "Camera", productURLText: "https://shop.example/camera")
    XCTAssertFalse(valid.validationIssues().contains { $0.field == "productURL" })
  }

  func testPriceRequiresValidCurrency() {
    let draft = WishlistItemDraft(productName: "Camera", estimatedPrice: 10, currency: "AU")
    XCTAssertTrue(draft.validationIssues().contains { $0.field == "currency" })
  }

  func testMoneyNormalizesCurrency() throws {
    let money = try Money(amount: 19.95, currencyCode: "aud")
    XCTAssertEqual(money.currencyCode, "AUD")
  }

  func testNegativeMoneyIsRejected() {
    XCTAssertThrowsError(try Money(amount: -0.01, currencyCode: "AUD"))
  }

  func testNonWantedStatusesCannotBeReserved() {
    XCTAssertTrue(WishlistItemStatus.wanted.canBeReserved)
    XCTAssertFalse(WishlistItemStatus.received.canBeReserved)
    XCTAssertFalse(WishlistItemStatus.purchasedByOwner.canBeReserved)
    XCTAssertFalse(WishlistItemStatus.noLongerWanted.canBeReserved)
  }
}
