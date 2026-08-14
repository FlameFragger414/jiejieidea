import Foundation
import XCTest

@testable import WishlistCore

final class AuthenticationStateMachineTests: XCTestCase {
  private let mia = AuthenticatedUser(
    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
    email: "mia.owner@example.invalid"
  )
  private let leo = AuthenticatedUser(
    id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
  )

  func testStartsWhileRestoringStoredSession() {
    let machine = AuthenticationStateMachine()
    XCTAssertEqual(machine.phase, .restoringSession)
    XCTAssertTrue(machine.phase.isBusy)
  }

  func testRestoringWithoutStoredSessionShowsSignIn() {
    var machine = AuthenticationStateMachine()
    machine.apply(.noSessionAvailable)
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testRestoredSessionWithIncompleteProfileRequiresOnboarding() {
    var machine = AuthenticationStateMachine()
    machine.apply(.sessionAvailable(mia, onboardingCompleted: false))
    XCTAssertEqual(machine.phase, .onboardingRequired(mia))
  }

  func testRestoredSessionWithCompletedProfileIsAuthenticated() {
    var machine = AuthenticationStateMachine()
    machine.apply(.sessionAvailable(mia, onboardingCompleted: true))
    XCTAssertEqual(machine.phase, .authenticated(mia))
    XCTAssertEqual(machine.phase.user, mia)
    XCTAssertFalse(machine.phase.isBusy)
  }

  func testSignInProgressAndCancellation() {
    var machine = AuthenticationStateMachine(phase: .signedOut)
    machine.apply(.signInStarted)
    XCTAssertEqual(machine.phase, .authenticating)
    machine.apply(.signInCancelled)
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testSignInFailureReturnsToSignedOutSoTheFormStaysUsable() {
    var machine = AuthenticationStateMachine(phase: .authenticating)
    machine.apply(.signInFailed(.rateLimited))
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testCompletingOnboardingPromotesToAuthenticated() {
    var machine = AuthenticationStateMachine(phase: .onboardingRequired(mia))
    machine.apply(.onboardingCompletionChanged(true))
    XCTAssertEqual(machine.phase, .authenticated(mia))
  }

  func testOnboardingCompletionIsIgnoredWithoutASession() {
    var machine = AuthenticationStateMachine(phase: .signedOut)
    machine.apply(.onboardingCompletionChanged(true))
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testTokenRefreshKeepsCurrentPhaseAndUpdatesIdentity() {
    let renamed = AuthenticatedUser(id: mia.id, email: "mia.new@example.invalid")
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.sessionRefreshed(renamed))
    XCTAssertEqual(machine.phase, .authenticated(renamed))

    var onboarding = AuthenticationStateMachine(phase: .onboardingRequired(mia))
    onboarding.apply(.sessionRefreshed(renamed))
    XCTAssertEqual(onboarding.phase, .onboardingRequired(renamed))
  }

  func testStaleRefreshForAnotherUserIsIgnored() {
    var machine = AuthenticationStateMachine(phase: .signedOut)
    machine.apply(.sessionRefreshed(leo))
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testRefreshAfterSignOutDoesNotResurrectSession() {
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.signedOut)
    machine.apply(.sessionRefreshed(mia))
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testRefreshDuringRestorationCannotCreateASession() {
    var machine = AuthenticationStateMachine()
    machine.apply(.sessionRefreshed(mia))
    XCTAssertEqual(machine.phase, .restoringSession)

    var authenticating = AuthenticationStateMachine(phase: .authenticating)
    authenticating.apply(.sessionRefreshed(mia))
    XCTAssertEqual(authenticating.phase, .authenticating)
  }

  /// A refresh that reports a different account must not promote that account into the phase the
  /// previous person reached, because the new profile has not been read yet.
  func testRefreshForADifferentAccountReturnsToRestoration() {
    var authenticated = AuthenticationStateMachine(phase: .authenticated(mia))
    authenticated.apply(.sessionRefreshed(leo))
    XCTAssertEqual(authenticated.phase, .restoringSession)

    var onboarding = AuthenticationStateMachine(phase: .onboardingRequired(mia))
    onboarding.apply(.sessionRefreshed(leo))
    XCTAssertEqual(onboarding.phase, .restoringSession)

    var unverified = AuthenticationStateMachine(
      phase: .unverified(user: mia, problem: .offline)
    )
    unverified.apply(.sessionRefreshed(leo))
    XCTAssertEqual(unverified.phase, .restoringSession)
  }

  func testARefreshedIdentityIsFollowedByItsOwnProfileRead() {
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.sessionRefreshed(leo))
    machine.apply(.sessionAvailable(leo, onboardingCompleted: false))
    XCTAssertEqual(machine.phase, .onboardingRequired(leo))
  }

  /// Events can settle in any order. Whatever the order, a signed-out shell stays signed out until
  /// a session is reported again.
  func testOutOfOrderEventsAfterSignOutNeverAuthenticate() {
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.signedOut)
    machine.apply(.sessionRefreshed(mia))
    machine.apply(.profileUnavailable(mia, .offline))
    machine.apply(.onboardingCompletionChanged(true))
    machine.apply(.verificationUnavailable(.offline))
    machine.apply(.sessionRefreshed(leo))
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testExpiredSessionReturnsToSignedOut() {
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.sessionExpired)
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testSignOutFromOnboardingReturnsToSignedOut() {
    var machine = AuthenticationStateMachine(phase: .onboardingRequired(mia))
    machine.apply(.signedOut)
    XCTAssertEqual(machine.phase, .signedOut)
  }

  func testOfflineLaunchCannotVerifyStoredSession() {
    var machine = AuthenticationStateMachine()
    machine.apply(.verificationUnavailable(.offline))
    XCTAssertEqual(machine.phase, .unverified(user: nil, problem: .offline))
  }

  func testOfflineLaunchRecoversOnceTheProfileCanBeRead() {
    var machine = AuthenticationStateMachine()
    machine.apply(.verificationUnavailable(.offline))
    machine.apply(.sessionAvailable(mia, onboardingCompleted: true))
    XCTAssertEqual(machine.phase, .authenticated(mia))
  }

  func testUnreadableProfileKeepsIdentityButNotOnboardingPhase() {
    var machine = AuthenticationStateMachine()
    machine.apply(.profileUnavailable(mia, .offline))
    XCTAssertEqual(machine.phase, .unverified(user: mia, problem: .offline))
    XCTAssertEqual(machine.phase.user, mia)
  }

  func testRefreshWhileProfileIsUnreadableKeepsTheReportedProblem() {
    var machine = AuthenticationStateMachine()
    machine.apply(.profileUnavailable(mia, .offline))
    machine.apply(.sessionRefreshed(mia))
    XCTAssertEqual(machine.phase, .unverified(user: mia, problem: .offline))
  }

  func testUnreadableProfileNeverReplacesAKnownPhase() {
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.profileUnavailable(mia, .serviceUnavailable))
    XCTAssertEqual(machine.phase, .authenticated(mia))
  }

  func testAProfileReadThatFailsAfterSignOutStaysSignedOut() {
    var machine = AuthenticationStateMachine(phase: .signedOut)
    machine.apply(.profileUnavailable(mia, .offline))
    XCTAssertEqual(machine.phase, .signedOut)
    XCTAssertNil(machine.phase.user)
  }

  func testConnectivityProblemNeverDowngradesAnEstablishedPhase() {
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.verificationUnavailable(.serviceUnavailable))
    XCTAssertEqual(machine.phase, .authenticated(mia))

    var onboarding = AuthenticationStateMachine(phase: .onboardingRequired(mia))
    onboarding.apply(.verificationUnavailable(.offline))
    XCTAssertEqual(onboarding.phase, .onboardingRequired(mia))
  }

  func testSignInStartedDoesNotInterruptAnEstablishedSession() {
    var machine = AuthenticationStateMachine(phase: .authenticated(mia))
    machine.apply(.signInStarted)
    XCTAssertEqual(machine.phase, .authenticated(mia))
  }

  func testUnverifiedPhaseRecoversAfterRestoration() {
    var machine = AuthenticationStateMachine(phase: .unverified(user: mia, problem: .offline))
    machine.apply(.restorationStarted)
    XCTAssertEqual(machine.phase, .restoringSession)
    machine.apply(.sessionAvailable(mia, onboardingCompleted: false))
    XCTAssertEqual(machine.phase, .onboardingRequired(mia))
  }
}
