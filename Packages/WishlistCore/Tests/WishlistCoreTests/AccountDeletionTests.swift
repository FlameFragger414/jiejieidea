import Foundation
import XCTest

@testable import WishlistCore

final class AccountDeletionTests: XCTestCase {
  func testConfirmationRequiresTheExactPhraseIgnoringCaseAndPadding() {
    XCTAssertTrue(AccountDeletionConfirmation.matches("DELETE"))
    XCTAssertTrue(AccountDeletionConfirmation.matches(" delete "))
    XCTAssertFalse(AccountDeletionConfirmation.matches(""))
    XCTAssertFalse(AccountDeletionConfirmation.matches("delete my account"))
    XCTAssertFalse(AccountDeletionConfirmation.matches("delet"))
  }

  func testDeletionRequiresConfirmationBeforeItRuns() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    XCTAssertEqual(request.state, .confirming)
    XCTAssertEqual(request.submit(confirmationText: "yes"), .confirmationMismatch)
    XCTAssertEqual(request.state, .confirming)
  }

  func testConfirmedDeletionRunsOnceAndReportsSuccess() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    XCTAssertEqual(request.submit(confirmationText: "DELETE"), .delete)
    XCTAssertTrue(request.state.isDeleting)
    XCTAssertEqual(request.submit(confirmationText: "DELETE"), .alreadyInFlight)

    request.markDeleted()
    XCTAssertEqual(request.state, .deleted)
  }

  func testFailureIsSurfacedAndDoesNotClaimDeletion() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    _ = request.submit(confirmationText: "delete")
    request.markFailed(.recentSignInRequired)
    XCTAssertEqual(request.state, .failed(.recentSignInRequired))
    XCTAssertEqual(request.state.failure, .recentSignInRequired)
  }

  func testCancellationIsIgnoredOnceDeletionStarted() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    _ = request.submit(confirmationText: "DELETE")
    request.cancel()
    XCTAssertTrue(request.state.isDeleting)
  }

  func testDeletedAccountCannotReopenTheConfirmation() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    _ = request.submit(confirmationText: "DELETE")
    request.markDeleted()
    request.beginConfirmation()
    XCTAssertEqual(request.state, .deleted)
  }

  /// The deleted state has to be terminal in every direction, or a second server request can be
  /// issued for an account that is already gone.
  func testDeletedAccountCannotStartDeletingAgain() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    _ = request.submit(confirmationText: "DELETE")
    request.markDeleted()

    XCTAssertEqual(request.submit(confirmationText: "DELETE"), .alreadyInFlight)
    XCTAssertEqual(request.state, .deleted)
    request.cancel()
    XCTAssertEqual(request.state, .deleted)
  }

  /// A failure is not terminal: the person must be able to try again.
  func testAFailedDeletionCanBeRetried() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    _ = request.submit(confirmationText: "DELETE")
    request.markFailed(.serviceUnavailable)

    XCTAssertEqual(request.submit(confirmationText: "DELETE"), .delete)
    XCTAssertTrue(request.state.isDeleting)
  }

  func testLateCompletionAfterAFailureIsIgnored() {
    var request = AccountDeletionRequest()
    request.beginConfirmation()
    _ = request.submit(confirmationText: "DELETE")
    request.markFailed(.serviceUnavailable)
    request.markDeleted()
    XCTAssertEqual(request.state, .failed(.serviceUnavailable))
  }
}
