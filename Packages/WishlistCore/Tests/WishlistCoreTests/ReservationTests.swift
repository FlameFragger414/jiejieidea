import Foundation
import XCTest

@testable import WishlistCore

final class ReservationTests: XCTestCase {
  func testAvailabilitySubtractsActiveQuantity() throws {
    let availability = try ItemAvailability(desiredQuantity: 3, activeReservedQuantity: 2)
    XCTAssertEqual(availability.remainingQuantity, 1)
    XCTAssertTrue(availability.canReserve(1))
    XCTAssertFalse(availability.canReserve(2))
  }

  func testSoldOutAvailabilityRejectsReservation() throws {
    let availability = try ItemAvailability(desiredQuantity: 1, activeReservedQuantity: 1)
    XCTAssertFalse(availability.isAvailable)
    XCTAssertFalse(availability.canReserve(1))
  }

  func testOverReservationStateIsRejected() {
    XCTAssertThrowsError(try ItemAvailability(desiredQuantity: 1, activeReservedQuantity: 2))
  }

  func testReservationCapacityStatuses() {
    XCTAssertTrue(GiftReservationStatus.reserved.holdsCapacity)
    XCTAssertTrue(GiftReservationStatus.purchased.holdsCapacity)
    XCTAssertFalse(GiftReservationStatus.cancelled.holdsCapacity)
    XCTAssertFalse(GiftReservationStatus.unavailable.holdsCapacity)
  }

  func testReservationRequestTrimsEmptyNote() throws {
    let request = try ReservationRequest(itemID: UUID(), quantity: 1, privateNote: "  ")
    XCTAssertNil(request.privateNote)
  }

  func testReservationRequestRejectsLongNote() {
    XCTAssertThrowsError(
      try ReservationRequest(
        itemID: UUID(), quantity: 1, privateNote: String(repeating: "x", count: 1_001))
    )
  }

  func testReservationRequestEncodesRPCNames() throws {
    let itemID = UUID()
    let key = UUID()
    let request = try ReservationRequest(itemID: itemID, quantity: 2, idempotencyKey: key)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    XCTAssertEqual(object["p_item_id"] as? String, itemID.uuidString)
    XCTAssertEqual(object["p_quantity"] as? Int, 2)
    XCTAssertEqual(object["p_idempotency_key"] as? String, key.uuidString)
  }
}
