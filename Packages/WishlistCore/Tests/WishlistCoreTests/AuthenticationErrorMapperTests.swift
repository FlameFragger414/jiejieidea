import Foundation
import XCTest

@testable import WishlistCore

final class AuthenticationErrorMapperTests: XCTestCase {
  func testCancellationOutranksEveryOtherSignal() {
    XCTAssertEqual(
      AuthenticationErrorMapper.map(
        errorCode: "invalid_credentials",
        statusCode: 400,
        isCancellation: true
      ),
      .appleSignInCancelled
    )
  }

  func testOfflineOutranksServerCodes() {
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "over_request_rate_limit", isOffline: true),
      .offline
    )
  }

  func testMapsMagicLinkFailureCodes() {
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "over_email_send_rate_limit"), .rateLimited)
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: "otp_expired"), .linkExpired)
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: "email_address_invalid"), .invalidEmail)
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "email_address_not_authorized"), .emailNotAllowed)
  }

  func testMapsCallbackExchangeFailures() {
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: "bad_code_verifier"), .callbackInvalid)
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "flow_state_not_found"), .callbackInvalid)
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: "flow_state_expired"), .linkExpired)
  }

  func testMapsSessionAndAppleFailures() {
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: "session_not_found"), .sessionExpired)
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "refresh_token_already_used"), .sessionExpired)
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "provider_disabled"), .appleProviderNotConfigured)
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "invalid_credentials"), .appleCredentialRejected)
  }

  func testMapsAccountDeletionEdgeFunctionCodes() {
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "recent_sign_in_required", statusCode: 403),
      .recentSignInRequired
    )
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "invalid_token", statusCode: 401),
      .notSignedIn
    )
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "missing_authorization", statusCode: 401),
      .notSignedIn
    )
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "storage_cleanup_failed", statusCode: 502),
      .serviceUnavailable
    )
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "account_deletion_failed", statusCode: 502),
      .serviceUnavailable
    )
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: "server_misconfigured", statusCode: 500),
      .serviceUnavailable
    )
  }

  func testFallsBackToStatusCodeWhenNoErrorCodeIsSupplied() {
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: nil, statusCode: 401), .notSignedIn)
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: nil, statusCode: 403), .sessionExpired)
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: nil, statusCode: 422), .callbackInvalid)
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: nil, statusCode: 429), .rateLimited)
    XCTAssertEqual(
      AuthenticationErrorMapper.map(errorCode: nil, statusCode: 503), .serviceUnavailable)
  }

  func testUnknownInputStaysUnknown() {
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: nil), .unknown)
    XCTAssertEqual(AuthenticationErrorMapper.map(errorCode: "brand_new_server_code"), .unknown)
  }

  func testEveryFailureHasNonEmptyUserSafeCopy() {
    let failures: [AuthenticationFailure] = [
      .invalidEmail, .emailNotAllowed, .rateLimited, .linkExpired, .callbackInvalid,
      .appleSignInCancelled, .appleIdentityTokenMissing, .appleCredentialRejected,
      .appleProviderNotConfigured, .sessionExpired, .notSignedIn, .recentSignInRequired,
      .offline, .timedOut, .serviceUnavailable, .unknown,
    ]
    for failure in failures {
      XCTAssertFalse(failure.userMessage.isEmpty, "\(failure) has no message")
      XCTAssertFalse(
        failure.userMessage.lowercased().contains("postgres"),
        "\(failure) leaks a database detail"
      )
    }
  }

  func testOnlyDeliberateCancellationIsTreatedAsCancellation() {
    XCTAssertTrue(AuthenticationFailure.appleSignInCancelled.isCancellation)
    XCTAssertFalse(AuthenticationFailure.appleCredentialRejected.isCancellation)
  }

  func testRetryableFailuresAreLimitedToTransientProblems() {
    XCTAssertTrue(AuthenticationFailure.offline.isRetryable)
    XCTAssertTrue(AuthenticationFailure.timedOut.isRetryable)
    XCTAssertTrue(AuthenticationFailure.serviceUnavailable.isRetryable)
    XCTAssertFalse(AuthenticationFailure.invalidEmail.isRetryable)
    XCTAssertFalse(AuthenticationFailure.linkExpired.isRetryable)
  }
}
