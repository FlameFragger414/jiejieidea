import Foundation
import WishlistCore
import XCTest

@MainActor
final class SessionControllerTests: XCTestCase {
  private func makeController(
    authentication: FakeAuthenticationService,
    profiles: FakeProfileService
  ) -> SessionController {
    SessionController(
      configuration: TestFixtures.configuration,
      authentication: authentication,
      profiles: profiles
    )
  }

  /// Polls on the main actor until `condition` holds, so tests do not depend on a fixed delay.
  private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 5,
    _ condition: @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for \(description)")
  }

  // MARK: - Session restoration

  func testRestoringACompleteProfileSignsThePersonIn() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    XCTAssertEqual(controller.phase, .restoringSession)
    controller.start()
    authentication.emit(.restored(TestFixtures.user))

    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }
    XCTAssertEqual(controller.profile?.id, TestFixtures.ownerID)
  }

  func testARestoredSessionEmittedBeforeObservationStartsIsStillApplied() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    authentication.emit(.restored(TestFixtures.user))
    controller.start()

    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }
  }

  func testRestoringAnIncompleteProfileRequiresOnboarding() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(
      profile: TestFixtures.profile(
        displayName: UserProfile.seededDisplayName,
        onboardingCompleted: false
      )
    )
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))

    try await waitUntil("onboarding") {
      controller.phase == .onboardingRequired(TestFixtures.user)
    }
  }

  func testNoStoredSessionShowsSignIn() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.noSession)

    try await waitUntil("the signed-out phase") { controller.phase == .signedOut }
    XCTAssertNil(controller.profile)
  }

  func testAnOfflineProfileReadLeavesTheSessionUnverified() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    profiles.setLoadResult(.failure(AuthenticationFailure.offline))
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))

    try await waitUntil("the unverified phase") {
      controller.phase == .unverified(user: TestFixtures.user, problem: .offline)
    }
    XCTAssertNil(controller.profile)
  }

  func testRetryingVerificationRecoversFromOffline() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    profiles.setLoadResult(.failure(AuthenticationFailure.offline))
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the unverified phase") {
      if case .unverified = controller.phase { return true }
      return false
    }

    authentication.setVerifyResult(.success(TestFixtures.user))
    profiles.setLoadResult(.success(TestFixtures.profile()))
    await controller.retryVerification()

    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.user))
  }

  func testStartIsIdempotentSoOnlyOneObservationRuns() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    controller.start()
    authentication.emit(.restored(TestFixtures.user))

    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }
    XCTAssertEqual(profiles.recordedLoadCount, 1)
  }

  // MARK: - Magic links

  func testAnInvalidAddressNeverReachesTheService() {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.emailField = "mia@invalid"
    controller.requestMagicLink()

    XCTAssertEqual(authentication.sentAddressCount, 0)
    XCTAssertEqual(controller.magicLink.state.failure, .invalidEmail)
    XCTAssertNotNil(controller.magicLinkFieldIssue)
  }

  func testASuccessfulRequestReportsThatTheEmailWasSent() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.emailField = " Mia@Example.INVALID "
    controller.requestMagicLink()

    try await waitUntil("the sent state") { controller.magicLink.state.didSend }
    XCTAssertEqual(authentication.lastSentAddress?.normalized, "mia@example.invalid")
    XCTAssertEqual(authentication.sentAddressCount, 1)
  }

  func testAFailedRequestNeverClaimsTheEmailWasSent() async throws {
    let authentication = FakeAuthenticationService()
    authentication.setMagicLinkResult(.failure(.rateLimited))
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.emailField = "mia@example.invalid"
    controller.requestMagicLink()

    try await waitUntil("the failure state") { controller.magicLink.state.failure != nil }
    XCTAssertFalse(controller.magicLink.state.didSend)
    XCTAssertEqual(controller.magicLink.state.failure, .rateLimited)
  }

  func testASecondSubmissionWhileSendingIsIgnored() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.emailField = "mia@example.invalid"
    controller.requestMagicLink()
    controller.requestMagicLink()

    try await waitUntil("the sent state") { controller.magicLink.state.didSend }
    XCTAssertEqual(authentication.sentAddressCount, 1)
  }

  // MARK: - Callback handling

  func testAnUnrelatedURLIsNotTreatedAsACallback() async {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    let handled = await controller.handle(url: URL(string: "https://example.invalid/anything")!)

    XCTAssertFalse(handled)
    XCTAssertEqual(authentication.callbackCount, 0)
  }

  func testAMalformedCallbackIsRejectedBeforeReachingTheSDK() async {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    let handled = await controller.handle(url: URL(string: "jiejie-debug://auth/callback")!)

    XCTAssertTrue(handled)
    XCTAssertEqual(authentication.callbackCount, 0)
    XCTAssertEqual(controller.magicLink.state.failure, .callbackInvalid)
  }

  func testAValidCallbackCompletesSignIn() async throws {
    let authentication = FakeAuthenticationService()
    authentication.setCallbackResult(.success(TestFixtures.user))
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    let handled = await controller.handle(
      url: URL(string: "jiejie-debug://auth/callback?code=abcdefgh12345678")!
    )

    XCTAssertTrue(handled)
    XCTAssertEqual(authentication.callbackCount, 1)
    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.user))
  }

  func testAnExpiredCallbackSurfacesTheProviderFailure() async {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    _ = await controller.handle(
      url: URL(string: "jiejie-debug://auth/callback?error_code=otp_expired")!
    )

    XCTAssertEqual(authentication.callbackCount, 0)
    XCTAssertEqual(controller.magicLink.state.failure, .linkExpired)
    XCTAssertEqual(controller.phase, .signedOut)
  }

  // MARK: - Sign in with Apple

  func testACancelledAppleSignInIsNotShownAsAnError() async {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    await controller.completeAppleSignIn(.failure(.appleSignInCancelled))

    XCTAssertNil(controller.appleSignInFailure)
    XCTAssertEqual(controller.phase, .signedOut)
    XCTAssertEqual(authentication.appleCredentialCount, 0)
  }

  func testAMissingAppleTokenIsShownAsAnError() async {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    await controller.completeAppleSignIn(.failure(.appleIdentityTokenMissing))

    XCTAssertEqual(controller.appleSignInFailure, .appleIdentityTokenMissing)
    XCTAssertEqual(controller.phase, .signedOut)
  }

  func testAnAppleCredentialSignsThePersonIn() async throws {
    let authentication = FakeAuthenticationService()
    authentication.setAppleResult(.success(TestFixtures.user))
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    await controller.completeAppleSignIn(.credential(try TestFixtures.appleCredential()))

    XCTAssertEqual(authentication.appleCredentialCount, 1)
    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.user))
    XCTAssertNil(controller.appleSignInFailure)
  }

  func testARejectedAppleCredentialReturnsToTheSignInScreen() async throws {
    let authentication = FakeAuthenticationService()
    authentication.setAppleResult(.failure(.appleProviderNotConfigured))
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    await controller.completeAppleSignIn(.credential(try TestFixtures.appleCredential()))

    XCTAssertEqual(controller.appleSignInFailure, .appleProviderNotConfigured)
    XCTAssertEqual(controller.phase, .signedOut)
  }

  // MARK: - Sign out

  func testSigningOutClearsEverySignedInDetail() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }

    controller.emailField = "mia@example.invalid"
    await controller.signOut()

    XCTAssertEqual(authentication.recordedSignOutCount, 1)
    XCTAssertEqual(controller.phase, .signedOut)
    XCTAssertNil(controller.profile)
    XCTAssertEqual(controller.emailField, "")
    XCTAssertEqual(controller.magicLink.state, .idle)
  }

  func testSigningOutStillEndsTheSessionWhenTheServerCallFails() async {
    let authentication = FakeAuthenticationService()
    authentication.setSignOutResult(.failure(.serviceUnavailable))
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    await controller.signOut()

    XCTAssertEqual(controller.phase, .signedOut)
    XCTAssertNil(controller.profile)
  }

  func testAProfileLoadThatFinishesAfterSignOutIsDiscarded() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    profiles.setLoadDelay(nanoseconds: 200_000_000)
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the profile read to start") { profiles.recordedLoadCount == 1 }

    await controller.signOut()
    try await Task.sleep(nanoseconds: 400_000_000)

    XCTAssertEqual(controller.phase, .signedOut)
    XCTAssertNil(controller.profile)
  }

  func testAnExpiredSessionEventReturnsToSignIn() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }

    authentication.emit(.signedOut)
    try await waitUntil("the signed-out phase") { controller.phase == .signedOut }
    XCTAssertNil(controller.profile)
  }

  func testATokenRefreshKeepsThePersonSignedIn() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }

    authentication.emit(.refreshed(TestFixtures.user))
    try await Task.sleep(nanoseconds: 100_000_000)

    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.user))
    XCTAssertEqual(profiles.recordedLoadCount, 1)
  }

  // MARK: - Profile completion

  func testCompletingOnboardingPromotesTheShell() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(
      profile: TestFixtures.profile(onboardingCompleted: false)
    )
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("onboarding") {
      controller.phase == .onboardingRequired(TestFixtures.user)
    }

    controller.profileDidChange(TestFixtures.profile(onboardingCompleted: true))

    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.user))
    XCTAssertEqual(controller.profile?.onboardingCompleted, true)
  }
}
