import Foundation
import XCTest

@testable import WishlistCore

final class AsyncOperationSequenceTests: XCTestCase {
  func testNewestTokenIsTheOnlyCurrentOne() {
    var sequence = AsyncOperationSequence()
    let first = sequence.start()
    XCTAssertTrue(sequence.isCurrent(first))

    let second = sequence.start()
    XCTAssertFalse(sequence.isCurrent(first))
    XCTAssertTrue(sequence.isCurrent(second))
    XCTAssertLessThan(first, second)
  }

  func testCancelAllInvalidatesOutstandingWork() {
    var sequence = AsyncOperationSequence()
    let token = sequence.start()
    sequence.cancelAll()
    XCTAssertFalse(sequence.isCurrent(token))
  }

  func testStaleResultIsDiscardedWhenAppliedOutOfOrder() {
    var sequence = AsyncOperationSequence()
    var applied: [String] = []

    let slowToken = sequence.start()
    let fastToken = sequence.start()

    if sequence.isCurrent(fastToken) { applied.append("fast") }
    if sequence.isCurrent(slowToken) { applied.append("slow") }

    XCTAssertEqual(applied, ["fast"])
  }

  func testTokensFromSeparateSequencesDoNotInterfere() {
    var profileLoads = AsyncOperationSequence()
    var avatarLoads = AsyncOperationSequence()

    let profileToken = profileLoads.start()
    _ = avatarLoads.start()
    _ = avatarLoads.start()

    XCTAssertTrue(profileLoads.isCurrent(profileToken))
  }
}
