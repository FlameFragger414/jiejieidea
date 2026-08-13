import XCTest

@testable import WishlistCore

final class BackendErrorMapperTests: XCTestCase {
  func testMapsReservationErrors() {
    XCTAssertEqual(BackendErrorMapper.map(code: "insufficient_quantity"), .insufficientQuantity)
    XCTAssertEqual(BackendErrorMapper.map(code: "wishlist_item_unavailable"), .itemUnavailable)
    XCTAssertEqual(BackendErrorMapper.map(code: "reservation_not_active"), .reservationNotActive)
  }

  func testMapsAccessErrorsWithoutRawMessage() {
    XCTAssertEqual(BackendErrorMapper.map(code: "wishlist_access_denied"), .accessDenied)
    XCTAssertEqual(BackendErrorMapper.map(code: "403"), .accessDenied)
  }

  func testOfflineTakesPrecedence() {
    XCTAssertEqual(BackendErrorMapper.map(code: "insufficient_quantity", isOffline: true), .offline)
  }

  func testUnknownServerCodeUsesSafeFallback() {
    XCTAssertEqual(BackendErrorMapper.map(code: "raw-database-detail"), .unknown)
    XCTAssertEqual(BackendErrorMapper.map(code: nil), .unknown)
  }
}
