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
  @Published private(set) var profile: UserProfile?
  @Published private(set) var magicLink = MagicLinkRequest()
  @Published private(set) var appleSignInFailure: AuthenticationFailure?
  @Published private(set) var configurationProblem: ConfigurationError?
  @Published var emailField = ""

  let appleSignInEnabled: Bool

  private let authentication: (any AuthenticationService)?
  private let profiles: (any ProfileService)?
  private let deepLinkParser: DeepLinkParser?
  private let callbackParser: AuthenticationCallbackParser?

  private var machine = AuthenticationStateMachine()
  private var observationTask: Task<Void, Never>?
  private var magicLinkTask: Task<Void, Never>?
  private var profileLoads = AsyncOperationSequence()

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

  var profileService: (any ProfileService)? { profiles }

  var isConfigured: Bool { configurationProblem == nil }

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

  func stop() {
    observationTask?.cancel()
    observationTask = nil
    magicLinkTask?.cancel()
    magicLinkTask = nil
    profileLoads.cancelAll()
  }

  private func handle(_ event: AuthenticationServiceEvent) async {
    switch event {
    case .noSession:
      apply(.noSessionAvailable)
      profile = nil
    case .restored(let user), .signedIn(let user):
      await loadProfileAndAnnounce(for: user)
    case .refreshed(let user), .userUpdated(let user):
      apply(.sessionRefreshed(user))
      if profile == nil {
        await loadProfileAndAnnounce(for: user)
      }
    case .signedOut:
      profileLoads.cancelAll()
      profile = nil
      magicLink = MagicLinkRequest()
      appleSignInFailure = nil
      apply(.signedOut)
    }
  }

  private func loadProfileAndAnnounce(for user: AuthenticatedUser) async {
    guard let profiles else { return }

    let token = profileLoads.start()
    do {
      let loaded = try await profiles.loadProfile(userID: user.id)
      // A newer load, a sign-out, or a different account superseded this request.
      guard profileLoads.isCurrent(token) else { return }
      profile = loaded
      apply(.sessionAvailable(user, onboardingCompleted: loaded.onboardingCompleted))
    } catch {
      guard profileLoads.isCurrent(token) else { return }
      let failure = ProfileFailureMapping.error(for: error).authenticationFailure ?? .unknown
      switch failure {
      case .offline, .timedOut:
        apply(.profileUnavailable(user, .offline))
      case .serviceUnavailable, .unknown:
        apply(.profileUnavailable(user, .serviceUnavailable))
      case .sessionExpired, .notSignedIn:
        apply(.sessionExpired)
      default:
        apply(.profileUnavailable(user, .serviceUnavailable))
      }
    }
  }

  /// Re-reads the session and profile, for example after the person taps "Try again" while offline.
  func retryVerification() async {
    guard let authentication else { return }
    apply(.restorationStarted)
    do {
      let user = try await authentication.verifiedUser()
      await loadProfileAndAnnounce(for: user)
    } catch let failure as AuthenticationFailure {
      switch failure {
      case .offline, .timedOut:
        apply(.verificationUnavailable(.offline))
      case .sessionExpired, .notSignedIn:
        apply(.sessionExpired)
      default:
        apply(.verificationUnavailable(.serviceUnavailable))
      }
    } catch {
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
    guard callbackParser.parse(callbackURL) != nil else {
      appleSignInFailure = nil
      magicLink.markFailed(.callbackInvalid)
      return true
    }

    apply(.signInStarted)
    do {
      let user = try await authentication.completeSignIn(callback: callbackURL)
      magicLink = MagicLinkRequest()
      await loadProfileAndAnnounce(for: user)
    } catch {
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
      apply(.signInStarted)
      do {
        let user = try await authentication.signInWithApple(credential: credential)
        await loadProfileAndAnnounce(for: user)
      } catch {
        let failure = AuthenticationFailureMapping.failure(for: error)
        appleSignInFailure = failure.isCancellation ? nil : failure
        apply(.signInFailed(failure))
      }
    }
  }

  // MARK: - Session end

  func signOut() async {
    guard let authentication else { return }
    profileLoads.cancelAll()
    // The phase moves as soon as the local session is discarded, so a failed network call cannot
    // leave the person looking at an account they no longer have a session for.
    try? await authentication.signOut()
    profile = nil
    magicLink = MagicLinkRequest()
    appleSignInFailure = nil
    emailField = ""
    apply(.signedOut)
  }

  /// Called after the account was deleted server-side.
  func accountWasDeleted() async {
    await signOut()
  }

  // MARK: - Profile updates

  func profileDidChange(_ updated: UserProfile) {
    profile = updated
    apply(.onboardingCompletionChanged(updated.onboardingCompleted))
  }

  private func apply(_ event: AuthenticationEvent) {
    machine.apply(event)
    phase = machine.phase
  }
}
