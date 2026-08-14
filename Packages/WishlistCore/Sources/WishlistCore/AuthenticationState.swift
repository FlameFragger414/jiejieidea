import Foundation

/// The signed-in identity the app is allowed to know about locally.
///
/// Access and refresh tokens are deliberately absent: they stay inside the authentication SDK's
/// Keychain-backed storage and never reach presentation state.
public struct AuthenticatedUser: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let email: String?

  public init(id: UUID, email: String? = nil) {
    self.id = id
    self.email = email
  }
}

/// Why the app cannot currently confirm whether a stored session is still valid.
public enum SessionVerificationProblem: Equatable, Sendable {
  case offline
  case serviceUnavailable

  public var userMessage: String {
    switch self {
    case .offline:
      "You’re offline, so Jiejie can’t confirm your sign-in yet."
    case .serviceUnavailable:
      "Jiejie can’t reach the sign-in service right now."
    }
  }
}

/// The mutually exclusive states the application shell can be in.
public enum AuthenticationPhase: Equatable, Sendable {
  /// Launch-time restoration of a stored session has not finished.
  case restoringSession
  /// No session exists; the sign-in screen is shown.
  case signedOut
  /// A sign-in request is in flight.
  case authenticating
  /// A session exists but the profile has not completed onboarding.
  case onboardingRequired(AuthenticatedUser)
  /// A session exists and onboarding is complete.
  case authenticated(AuthenticatedUser)
  /// A session may exist but could not be verified, usually because the device is offline.
  case unverified(user: AuthenticatedUser?, problem: SessionVerificationProblem)

  public var user: AuthenticatedUser? {
    switch self {
    case .onboardingRequired(let user), .authenticated(let user):
      user
    case .unverified(let user, _):
      user
    case .restoringSession, .signedOut, .authenticating:
      nil
    }
  }

  /// `true` while the shell should show progress rather than content or a sign-in form.
  public var isBusy: Bool {
    switch self {
    case .restoringSession, .authenticating:
      true
    case .signedOut, .onboardingRequired, .authenticated, .unverified:
      false
    }
  }
}

/// Everything that can move the shell between phases.
public enum AuthenticationEvent: Equatable, Sendable {
  case restorationStarted
  case signInStarted
  case signInCancelled
  case signInFailed(AuthenticationFailure)
  /// A session became available, either restored at launch or created by a sign-in.
  case sessionAvailable(AuthenticatedUser, onboardingCompleted: Bool)
  /// The stored session was refreshed; the identity may have been re-read.
  case sessionRefreshed(AuthenticatedUser)
  /// The profile record changed, typically when onboarding completed.
  case onboardingCompletionChanged(Bool)
  /// A session exists, but the profile read failed, so the onboarding phase is unknown.
  case profileUnavailable(AuthenticatedUser, SessionVerificationProblem)
  case noSessionAvailable
  case sessionExpired
  case signedOut
  case verificationUnavailable(SessionVerificationProblem)
}

/// A deterministic reducer for the shell's authentication phase.
///
/// Keeping the transitions in a value type means every ordering — including a refresh that arrives
/// after a sign-out, or an offline event during restoration — is covered by tests instead of being
/// implied by view code.
public struct AuthenticationStateMachine: Equatable, Sendable {
  public private(set) var phase: AuthenticationPhase

  public init(phase: AuthenticationPhase = .restoringSession) {
    self.phase = phase
  }

  public mutating func apply(_ event: AuthenticationEvent) {
    switch event {
    case .restorationStarted:
      phase = .restoringSession

    case .signInStarted:
      // A sign-in request never interrupts an established session.
      if phase.user == nil {
        phase = .authenticating
      }

    case .signInCancelled:
      if phase.user == nil {
        phase = .signedOut
      }

    case .signInFailed:
      // The failure itself is surfaced by the sign-in screen, which stays visible.
      if phase.user == nil {
        phase = .signedOut
      }

    case .sessionAvailable(let user, let onboardingCompleted):
      phase = onboardingCompleted ? .authenticated(user) : .onboardingRequired(user)

    case .sessionRefreshed(let user):
      switch phase {
      case .authenticated:
        phase = .authenticated(user)
      case .onboardingRequired:
        phase = .onboardingRequired(user)
      case .unverified(let previous, let problem) where previous?.id == user.id:
        // The identity is known but the profile still has not been read, so the phase is unchanged.
        phase = .unverified(user: user, problem: problem)
      case .restoringSession, .signedOut, .authenticating, .unverified:
        // A refresh for an unknown user is ignored; restoration reports the authoritative phase.
        break
      }

    case .onboardingCompletionChanged(let completed):
      guard let user = phase.user else { return }
      switch phase {
      case .authenticated, .onboardingRequired:
        phase = completed ? .authenticated(user) : .onboardingRequired(user)
      case .restoringSession, .signedOut, .authenticating, .unverified:
        break
      }

    case .profileUnavailable(let user, let problem):
      switch phase {
      case .authenticated, .onboardingRequired:
        // The last known onboarding phase is more useful than an unverified screen.
        break
      case .restoringSession, .signedOut, .authenticating, .unverified:
        phase = .unverified(user: user, problem: problem)
      }

    case .noSessionAvailable, .sessionExpired, .signedOut:
      phase = .signedOut

    case .verificationUnavailable(let problem):
      switch phase {
      case .restoringSession, .unverified:
        phase = .unverified(user: phase.user, problem: problem)
      case .authenticated, .onboardingRequired, .signedOut, .authenticating:
        // An established phase is never downgraded, and a signed-out shell reports connectivity
        // problems next to the sign-in controls instead of replacing them.
        break
      }
    }
  }
}
