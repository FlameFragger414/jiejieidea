import Foundation
import XCTest

@testable import WishlistCore

final class MagicLinkRequestTests: XCTestCase {
  func testValidSubmissionMovesToSending() throws {
    var request = MagicLinkRequest()
    let submission = request.submit(" Mia@Example.INVALID ")
    XCTAssertEqual(submission, .send(try EmailAddress("mia@example.invalid")))
    XCTAssertTrue(request.state.isSending)
    XCTAssertFalse(request.state.didSend)
    XCTAssertFalse(request.canSubmit)
  }

  func testInvalidAddressNeverStartsARequest() {
    var request = MagicLinkRequest()
    let submission = request.submit("mia@invalid")
    guard case .invalid(let issue) = submission else {
      return XCTFail("Expected an invalid submission, got \(submission)")
    }
    XCTAssertEqual(issue.field, "email")
    XCTAssertEqual(request.state.failure, .invalidEmail)
    XCTAssertFalse(request.state.didSend)
  }

  func testDuplicateSubmissionWhileSendingIsIgnored() {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    XCTAssertEqual(request.submit("mia@example.invalid"), .alreadyInFlight)
    XCTAssertTrue(request.state.isSending)
  }

  func testSuccessOnlyReportsSentAfterTheServerAccepted() throws {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    request.markSent()
    XCTAssertEqual(request.state, .sent(try EmailAddress("mia@example.invalid")))
    XCTAssertTrue(request.state.didSend)
  }

  func testFailureDoesNotClaimTheEmailWasSent() {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    request.markFailed(.serviceUnavailable)
    XCTAssertEqual(request.state, .failed(.serviceUnavailable))
    XCTAssertFalse(request.state.didSend)
  }

  func testOfflineFailureIsRetryable() {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    request.markFailed(.offline)
    XCTAssertEqual(request.state.failure, .offline)
    XCTAssertTrue(try XCTUnwrap(request.state.failure).isRetryable)
  }

  func testCancellationReturnsToIdleWithoutClaimingSuccess() {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    request.markCancelled()
    XCTAssertEqual(request.state, .idle)
    XCTAssertTrue(request.canSubmit)
  }

  func testLateCompletionOfACancelledRequestIsIgnored() {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    request.markCancelled()
    request.markSent()
    request.markFailed(.rateLimited)
    XCTAssertEqual(request.state, .idle)
  }

  func testResetClearsACompletedResultButNotAnInFlightOne() {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    request.reset()
    XCTAssertTrue(request.state.isSending)

    request.markSent()
    request.reset()
    XCTAssertEqual(request.state, .idle)
  }

  func testResubmissionIsAllowedAfterAFailure() {
    var request = MagicLinkRequest()
    _ = request.submit("mia@example.invalid")
    request.markFailed(.rateLimited)
    XCTAssertTrue(request.canSubmit)
    guard case .send = request.submit("mia@example.invalid") else {
      return XCTFail("Expected the retry to be allowed")
    }
  }
}
