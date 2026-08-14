import Combine
import Foundation
import WishlistCore

/// Owns the shell's authentication phase, the signed-in profile, and the sign-in requests.
///
/// The controller is the only place that talks to the authentication and profile services, so views
/// observe state instead of performing work, and every transition runs through the tested
/// `AuthenticationStateMachine`.
@MainActor
final class SessionController: ObservableObject {
  @Published private(set) var phase: AuthenticationPhase = .restoringSession
  @Published private(set) var profile: UserProfile? = nil
  @Published private(set) var magicLink = MagicLinkRequest()
  @Published private(set) var appleSignInFailure: AuthenticationFailure? = nil
  @Published private(set) var configurationProblem: ConfigurationError? = nil
  @Published var emailField = ""

  let appleSignInEnabled: Bool

  private let authentication: (any AuthenticationService)?
  private let profiles: (any ProfileService)?
  private let deepLinkParser: DeepLinkParser?
  private let callbackParser: AuthenticationCallbackParser?

  private var machine = AuthenticationStateMachine()
  private var observationTask: Task<Void, Never>?
  private var magicLinkTask: Task<Void, Never>?

  /// Invalidated by every identity transition: a sign-out, a sign-in, or a refresh that reports a
  /// different account. Work that started before the transition can then be recognised as stale and
  /// dropped instead of authenticating somebody who is no longer, or never was, signed in.
  private var sessionOperations = AsyncOperationSequence()
  /// The identity the published `profile` and `phase` belong to, or `nil` when no session is held.
  private var currentUserID: UUID?

  /// Production initializer. A missing or placeholder configuration is reported instead of crashing,
  /// so a fresh clone explains what to copy rather than failing silently.
  init() {
    do {
      let configuration = try AppConfiguration.load()
      let client = SupabaseClientFactory.make(configuration: configuration)
      authentication = SupabaseAuthenticationService(
        client: client,
        configuration: configuration
      )
      profiles = SupabaseProfileService(client: client)
      deepLinkParser = configuration.deepLinkParser
      callbackParser = configuration.callbackParser
      appleSignInEnabled = configuration.appleSignInEnabled
    } catch let error as ConfigurationError {
      authentication = nil
      profiles = nil
      deepLinkParser = nil
      callbackParser = nil
      appleSignInEnabled = false
      configurationProblem = error
    } catch {
      authentication = nil
      profiles = nil
      deepLinkParser = nil
      callbackParser = nil
      appleSignInEnabled = false
      configurationProblem = .missingLocalConfiguration
    }
  }

  init(
    configuration: AppConfiguration,
    authentication: any AuthenticationService,
    profiles: any ProfileService
  ) {
    self.authentication = authentication
    self.profiles = profiles
    deepLinkParser = configuration.deepLinkParser
    callbackParser = configuration.callbackParser
    appleSignInEnabled = configuration.appleSignInEnabled
  }

  deinit {
    // The observation task holds the authentication service and iterates its event stream forever,
    // so it has to end with the controller rather than outlive it.
    observationTask?.cancel()
    magicLinkTask?.cancel()
  }

  var profileService: (any ProfileService)? { profiles }

  // MARK: - Lifecycle

  /// Starts observing authentication changes. Safe to call more than once; later calls are ignored
  /// so a re-appearing view cannot open a second observation.
  func start() {
    guard let authentication, observationTask == nil else { return }

    observationTask = Task { [weak self] in
      for await event in authentication.events() {
        guard let self else { return }
        await self.handle(event)
      }
    }
  }

  private func handle(_ event: AuthenticationServiceEvent) async {
    switch event {
    case .noSession:
      discardSession()
      apply(.noSessionAvailable)
    case .restored(let user), .signedIn(let user):
      await beginSession(for: user)
    case .refreshed(let user), .userUpdated(let user):
      await continueSession(for: user)
    case .signedOut:
      endSession()
    }
  }

  // MARK: - Identity transitions

  /// Adopts `user` as the current identity and returns the token every later step must still own.
  ///
  /// Adopting an identity supersedes all outstanding work, so a refresh or profile read that was
  /// started for a previous identity — or for no identity at all — can no longer apply itself.
  private func adoptIdentity(_ user: AuthenticatedUser) -> AsyncOperationToken {
    if currentUserID != user.id {
      profile = nil
    }
    currentUserID = user.id
    return sessionOperations.start()
  }

  /// Drops the held identity and everything read for it, and makes in-flight work stale.
  private func discardSession() {
    sessionOperations.cancelAll()
    currentUserID = nil
    profile = nil
  }

  private func endSession() {
    magicLinkTask?.cancel()
    magicLinkTask = nil
    discardSession()
    magicLink = MagicLinkRequest()
    appleSignInFailure = nil
    apply(.signedOut)
  }

  private func beginSession(for user: AuthenticatedUser) async {
    let token = adoptIdentity(user)
    await loadProfileAndAnnounce(for: user, token: token)
  }

  /// Handles a token refresh or a user update for a session that already exists.
  private func continueSession(for user: AuthenticatedUser) async {
    guard let currentUserID else {
      // No session is held, so this refresh is either late or unsolicited. Acting on it would sign
      // somebody in who has already signed out.
      return
    }

    guard currentUserID == user.id else {
      // The refreshed session belongs to another account. `adoptIdentity` drops the previous
      // person's profile first, and the reducer moves to a neutral phase, so nothing from the old
      // identity is ever shown under the new one.
      let token = adoptIdentity(user)
      apply(.sessionRefreshed(user))
      await loadProfileAndAnnounce(for: user, token: token)
      return
    }

    apply(.sessionRefreshed(user))
    guard profile == nil else { return }
    await loadProfileAndAnnounce(for: user, token: sessionOperations.start())
  }

  private func loadProfileAndAnnounce(
    for user: AuthenticatedUser,
    token: AsyncOperationToken
  ) async {
    guard let profiles, sessionOperations.isCurrent(token) else { return }

    do {
      let loaded = try await profiles.loadProfile(userID: user.id)
      // A newer load, a sign-out, or a different account superseded this request.
      guard sessionOperations.isCurrent(token), currentUserID == user.id else { return }
      guard loaded.id == user.id else {
        // The row does not belong to the authenticated caller, so it is refused rather than shown.
        discardSession()
        apply(.sessionExpired)
        return
      }
      profile = loaded
      apply(.sessionAvailable(user, onboardingCompleted: loaded.onboardingCompleted))
    } catch {
      guard sessionOperations.isCurrent(token), currentUserID == user.id else { return }
      let failure = ProfileFailureMapping.error(for: error).authenticationFailure ?? .unknown
      switch failure {
      case .offline, .timedOut:
        apply(.profileUnavailable(user, .offline))
      case .sessionExpired, .notSignedIn:
        discardSession()
        apply(.sessionExpired)
      default:
        apply(.profileUnavailable(user, .serviceUnavailable))
      }
    }
  }

  /// Re-reads the session and profile, for example after the person taps "Try again" while offline.
  func retryVerification() async {
    guard let authentication else { return }
    let token = sessionOperations.start()
    apply(.restorationStarted)
    do {
      let user = try await authentication.verifiedUser()
      guard sessionOperations.isCurrent(token) else { return }
      await loadProfileAndAnnounce(for: user, token: adoptIdentity(user))
    } catch let failure as AuthenticationFailure {
      guard sessionOperations.isCurrent(token) else { return }
      switch failure {
      case .offline, .timedOut:
        apply(.verificationUnavailable(.offline))
      case .sessionExpired, .notSignedIn:
        discardSession()
        apply(.sessionExpired)
      default:
        apply(.verificationUnavailable(.serviceUnavailable))
      }
    } catch {
      guard sessionOperations.isCurrent(token) else { return }
      apply(.verificationUnavailable(.serviceUnavailable))
    }
  }

  // MARK: - Email magic link

  func requestMagicLink() {
    guard let authentication else { return }

    switch magicLink.submit(emailField) {
    case .alreadyInFlight, .invalid:
      return
    case .send(let address):
      magicLinkTask?.cancel()
      magicLinkTask = Task { [weak self] in
        do {
          try await authentication.sendMagicLink(to: address)
          guard let self, !Task.isCancelled else { return }
          magicLink.markSent()
        } catch is CancellationError {
          self?.magicLink.markCancelled()
        } catch {
          guard let self, !Task.isCancelled else { return }
          magicLink.markFailed(AuthenticationFailureMapping.failure(for: error))
        }
      }
    }
  }

  func resetMagicLink() {
    magicLinkTask?.cancel()
    magicLinkTask = nil
    // The first call clears an in-flight request, the second clears a finished result. Together
    // they always land on idle so the form cannot be left showing "Sending link…".
    magicLink.markCancelled()
    magicLink.reset()
  }

  var magicLinkFieldIssue: ValidationIssue? {
    guard !emailField.isEmpty, !EmailAddress.isValid(emailField) else { return nil }
    return ValidationIssue(field: "email", message: "Enter a valid email address.")
  }

  // MARK: - Deep links

  /// Handles an incoming URL. Returns `true` when the URL was an authentication callback for this
  /// build, so unrelated links can be routed elsewhere later.
  @discardableResult
  func handle(url: URL) async -> Bool {
    guard let authentication, let deepLinkParser, let callbackParser else { return false }
    guard case .authenticationCallback(let callbackURL) = deepLinkParser.parse(url) else {
      return false
    }

    appleSignInFailure = nil
    switch callbackParser.parse(callbackURL) {
    case .authorizationCode:
      break
    case .providerFailure(let code):
      // The provider already reported a failure, so there is nothing to exchange.
      let failure = AuthenticationErrorMapper.map(errorCode: code)
      magicLink = MagicLinkRequest(state: .failed(failure))
      apply(.signInFailed(failure))
      return true
    case nil:
      magicLink = MagicLinkRequest(state: .failed(.callbackInvalid))
      apply(.signInFailed(.callbackInvalid))
      return true
    }

    let token = sessionOperations.start()
    apply(.signInStarted)
    do {
      let user = try await authentication.completeSignIn(callback: callbackURL)
      guard sessionOperations.isCurrent(token) else { return true }
      magicLink = MagicLinkRequest()
      await loadProfileAndAnnounce(for: user, token: adoptIdentity(user))
    } catch {
      guard sessionOperations.isCurrent(token) else { return true }
      let failure = AuthenticationFailureMapping.failure(for: error)
      apply(.signInFailed(failure))
      magicLink = MagicLinkRequest(state: .failed(failure))
    }
    return true
  }

  // MARK: - Sign in with Apple

  func completeAppleSignIn(_ outcome: AppleSignInOutcome) async {
    guard let authentication else { return }

    switch outcome {
    case .failure(let failure):
      appleSignInFailure = failure.isCancellation ? nil : failure
      apply(failure.isCancellation ? .signInCancelled : .signInFailed(failure))
    case .credential(let credential):
      appleSignInFailure = nil
      let token = sessionOperations.start()
      apply(.signInStarted)
      do {
        let user = try await authentication.signInWithApple(credential: credential)
        guard sessionOperations.isCurrent(token) else { return }
        await loadProfileAndAnnounce(for: user, token: adoptIdentity(user))
      } catch {
        guard sessionOperations.isCurrent(token) else { return }
        let failure = AuthenticationFailureMapping.failure(for: error)
        appleSignInFailure = failure.isCancellation ? nil : failure
        apply(.signInFailed(failure))
      }
    }
  }

  // MARK: - Session end

  func signOut() async {
    guard let authentication else { return }
    // The local session ends before the network call, so a slow or failed sign-out cannot leave the
    // person looking at an account they no longer have a session for, and any request already in
    // flight is stale by the time it returns.
    endSession()
    emailField = ""
    try? await authentication.signOut()
  }

  /// Called after the account was deleted server-side.
  func accountWasDeleted() async {
    await signOut()
  }

  // MARK: - Profile updates

  func profileDidChange(_ updated: UserProfile) {
    // An edit that belongs to a previous identity must not be written over the current one.
    guard updated.id == currentUserID else { return }
    profile = updated
    apply(.onboardingCompletionChanged(updated.onboardingCompleted))
  }

  private func apply(_ event: AuthenticationEvent) {
    machine.apply(event)
    phase = machine.phase
  }
}
