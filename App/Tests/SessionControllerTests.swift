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

    // The refreshed session carries the same account with a re-read address, so observing the new
    // identity in the phase is a deterministic signal that the refresh was handled.
    let refreshed = AuthenticatedUser(id: TestFixtures.ownerID, email: "mia.new@example.invalid")
    authentication.emit(.refreshed(refreshed))
    try await waitUntil("the refreshed identity") {
      controller.phase == .authenticated(refreshed)
    }
    XCTAssertEqual(profiles.recordedLoadCount, 1)
  }

  // MARK: - Session lifecycle safety

  /// The profile read started before the sign-out completes afterwards. It must be discarded rather
  /// than authenticating somebody who has already signed out.
  func testAProfileLoadThatFinishesAfterSignOutNeverSignsThePersonBackIn() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    profiles.setLoadResult(.success(TestFixtures.profile()), for: TestFixtures.ownerID)
    profiles.setLoadResult(.success(TestFixtures.otherProfile()), for: TestFixtures.otherID)
    let gate = AsyncGate()
    profiles.setLoadGate(gate)
    let controller = makeController(authentication: authentication, profiles: profiles)
    let recorder = PhaseRecorder(controller)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    await gate.waitForArrivals(1)

    await controller.signOut()
    XCTAssertEqual(controller.phase, .signedOut)

    // Releasing the read lets the superseded load finish. Events are handled one at a time, so
    // reaching the second account proves the stale load was processed and dropped first.
    gate.open()
    authentication.emit(.signedIn(TestFixtures.otherUser))
    try await waitUntil("the second account") {
      controller.phase == .authenticated(TestFixtures.otherUser)
    }

    XCTAssertEqual(controller.profile?.id, TestFixtures.otherID)
    XCTAssertEqual(recorder.occurrences(of: .authenticated(TestFixtures.user)), 0)
  }

  /// The same rule for the refresh the "Try again" button starts.
  func testAVerificationThatFinishesAfterSignOutNeverSignsThePersonBackIn() async throws {
    let authentication = FakeAuthenticationService()
    authentication.setVerifyResult(.success(TestFixtures.user))
    let verifyGate = AsyncGate()
    authentication.setVerifyGate(verifyGate)
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)
    let recorder = PhaseRecorder(controller)

    controller.start()
    authentication.emit(.noSession)
    try await waitUntil("the signed-out phase") { controller.phase == .signedOut }

    let verification = Task { await controller.retryVerification() }
    await verifyGate.waitForArrivals(1)
    await controller.signOut()
    verifyGate.open()
    await verification.value

    XCTAssertEqual(controller.phase, .signedOut)
    XCTAssertNil(controller.profile)
    XCTAssertEqual(profiles.recordedLoadCount, 0)
    XCTAssertEqual(recorder.occurrences(of: .authenticated(TestFixtures.user)), 0)
  }

  func testARefreshEventThatArrivesAfterSignOutIsIgnored() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    profiles.setLoadResult(.success(TestFixtures.profile()), for: TestFixtures.ownerID)
    profiles.setLoadResult(.success(TestFixtures.otherProfile()), for: TestFixtures.otherID)
    let controller = makeController(authentication: authentication, profiles: profiles)
    let recorder = PhaseRecorder(controller)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }
    await controller.signOut()

    authentication.emit(.refreshed(TestFixtures.user))
    authentication.emit(.restored(TestFixtures.otherUser))
    try await waitUntil("the second account") {
      controller.phase == .authenticated(TestFixtures.otherUser)
    }

    // The late refresh read no profile at all, so it never had a result to apply.
    XCTAssertEqual(profiles.recordedLoadedUserIDs, [TestFixtures.ownerID, TestFixtures.otherID])
    XCTAssertEqual(recorder.occurrences(of: .authenticated(TestFixtures.user)), 1)
  }

  /// A refreshed session that reports a different account must not keep the previous person's
  /// profile, and must not show the new account under the previous person's onboarding phase.
  func testARefreshForADifferentUserNeverKeepsThePreviousProfile() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    profiles.setLoadResult(.success(TestFixtures.profile()), for: TestFixtures.ownerID)
    profiles.setLoadResult(.success(TestFixtures.otherProfile()), for: TestFixtures.otherID)
    let controller = makeController(authentication: authentication, profiles: profiles)
    let recorder = PhaseRecorder(controller)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }

    authentication.emit(.refreshed(TestFixtures.otherUser))
    try await waitUntil("the refreshed account") {
      controller.phase == .authenticated(TestFixtures.otherUser)
    }

    XCTAssertEqual(controller.profile?.id, TestFixtures.otherID)
    XCTAssertEqual(controller.profile?.displayName, "Leo Marsh")
    XCTAssertEqual(profiles.recordedLoadedUserIDs, [TestFixtures.ownerID, TestFixtures.otherID])
    // The neutral phase between the two identities is what stops the first person's profile from
    // ever being rendered under the second person's session.
    XCTAssertEqual(
      recorder.phases,
      [
        .restoringSession,
        .authenticated(TestFixtures.user),
        .restoringSession,
        .authenticated(TestFixtures.otherUser),
      ]
    )
  }

  /// A verification and a callback overlap, and the older one settles last.
  func testOverlappingSessionWorkAppliesOnlyTheNewestIdentity() async throws {
    let authentication = FakeAuthenticationService()
    authentication.setVerifyResult(.success(TestFixtures.user))
    authentication.setCallbackResult(.success(TestFixtures.otherUser))
    let verifyGate = AsyncGate()
    authentication.setVerifyGate(verifyGate)
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    profiles.setLoadResult(.success(TestFixtures.profile()), for: TestFixtures.ownerID)
    profiles.setLoadResult(.success(TestFixtures.otherProfile()), for: TestFixtures.otherID)
    let controller = makeController(authentication: authentication, profiles: profiles)

    let verification = Task { await controller.retryVerification() }
    await verifyGate.waitForArrivals(1)

    let handled = await controller.handle(
      url: URL(string: "jiejie-debug://auth/callback?code=abcdefgh12345678")!
    )
    XCTAssertTrue(handled)
    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.otherUser))

    verifyGate.open()
    await verification.value

    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.otherUser))
    XCTAssertEqual(controller.profile?.id, TestFixtures.otherID)
    // The superseded verification never reached a profile read for the account it resolved.
    XCTAssertEqual(profiles.recordedLoadedUserIDs, [TestFixtures.otherID])
  }

  /// Row Level Security should make this impossible, but a profile that does not belong to the
  /// authenticated caller must be refused rather than displayed.
  func testAProfileForAnotherAccountIsRefused() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.otherProfile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))

    try await waitUntil("the refused profile") { controller.phase == .signedOut }
    XCTAssertNil(controller.profile)
  }

  func testAProfileChangeForAnotherAccountIsIgnored() async throws {
    let authentication = FakeAuthenticationService()
    let profiles = FakeProfileService(profile: TestFixtures.profile())
    let controller = makeController(authentication: authentication, profiles: profiles)

    controller.start()
    authentication.emit(.restored(TestFixtures.user))
    try await waitUntil("the restored session") {
      controller.phase == .authenticated(TestFixtures.user)
    }

    controller.profileDidChange(TestFixtures.otherProfile(onboardingCompleted: false))

    XCTAssertEqual(controller.profile?.id, TestFixtures.ownerID)
    XCTAssertEqual(controller.phase, .authenticated(TestFixtures.user))
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
