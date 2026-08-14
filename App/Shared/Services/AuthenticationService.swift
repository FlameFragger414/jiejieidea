import Foundation
import Supabase
import WishlistCore

/// A change reported by the authentication SDK, reduced to what the shell needs.
enum AuthenticationServiceEvent: Equatable, Sendable {
  case restored(AuthenticatedUser)
  case signedIn(AuthenticatedUser)
  case refreshed(AuthenticatedUser)
  case userUpdated(AuthenticatedUser)
  case signedOut
  case noSession
}

/// The authentication surface the shell depends on.
///
/// The protocol keeps `SessionController` testable and stops view code from reaching into the SDK,
/// which is also what keeps tokens out of presentation state.
protocol AuthenticationService: Sendable {
  /// The session already restored from Keychain-backed storage, without a network round trip.
  func restoredUser() async -> AuthenticatedUser?
  /// Refreshes the stored session when needed and returns the verified identity.
  func verifiedUser() async throws -> AuthenticatedUser
  /// Emits an initial event for the stored session, then every later change.
  func events() -> AsyncStream<AuthenticationServiceEvent>
  func sendMagicLink(to address: EmailAddress) async throws
  /// Exchanges a validated callback URL for a session.
  func completeSignIn(callback url: URL) async throws -> AuthenticatedUser
  func signInWithApple(credential: AppleIdentityCredential) async throws -> AuthenticatedUser
  func signOut() async throws
}

/// Supabase-backed implementation.
struct SupabaseAuthenticationService: AuthenticationService {
  private let client: SupabaseClient
  private let callbackParser: AuthenticationCallbackParser
  private let redirectURL: URL

  init(client: SupabaseClient, configuration: AppConfiguration) {
    self.client = client
    callbackParser = configuration.callbackParser
    redirectURL = configuration.authCallbackURL
  }

  func restoredUser() async -> AuthenticatedUser? {
    client.auth.currentSession.map(AuthenticatedUser.init(session:))
  }

  func verifiedUser() async throws -> AuthenticatedUser {
    do {
      return AuthenticatedUser(session: try await client.auth.session)
    } catch {
      throw AuthenticationFailureMapping.failure(for: error)
    }
  }

  func events() -> AsyncStream<AuthenticationServiceEvent> {
    let changes = client.auth.authStateChanges
    return AsyncStream { continuation in
      let task = Task {
        for await (event, session) in changes {
          guard let serviceEvent = Self.serviceEvent(for: event, session: session) else { continue }
          continuation.yield(serviceEvent)
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func sendMagicLink(to address: EmailAddress) async throws {
    do {
      try await client.auth.signInWithOTP(
        email: address.normalized,
        redirectTo: redirectURL,
        shouldCreateUser: true
      )
    } catch {
      throw AuthenticationFailureMapping.failure(for: error)
    }
  }

  func completeSignIn(callback url: URL) async throws -> AuthenticatedUser {
    switch callbackParser.parse(url) {
    case .authorizationCode:
      break
    case .providerFailure(let code):
      throw AuthenticationErrorMapper.map(errorCode: code)
    case nil:
      throw AuthenticationFailure.callbackInvalid
    }

    do {
      // The original URL is handed to the SDK so it can read the PKCE parameters it wrote.
      return AuthenticatedUser(session: try await client.auth.session(from: url))
    } catch {
      throw AuthenticationFailureMapping.failure(for: error)
    }
  }

  func signInWithApple(credential: AppleIdentityCredential) async throws -> AuthenticatedUser {
    do {
      let session = try await client.auth.signInWithIdToken(
        credentials: OpenIDConnectCredentials(
          provider: .apple,
          idToken: credential.identityToken,
          nonce: credential.nonce.raw
        )
      )
      return AuthenticatedUser(session: session)
    } catch {
      throw AuthenticationFailureMapping.failure(for: error)
    }
  }

  func signOut() async throws {
    do {
      try await client.auth.signOut()
    } catch {
      let failure = AuthenticationFailureMapping.failure(for: error)
      // An already-invalid session is the desired end state, so it is not an error worth showing.
      guard failure != .sessionExpired, failure != .notSignedIn else { return }
      throw failure
    }
  }

  private static func serviceEvent(
    for event: AuthChangeEvent,
    session: Session?
  ) -> AuthenticationServiceEvent? {
    switch event {
    case .initialSession:
      guard let session else { return .noSession }
      return .restored(AuthenticatedUser(session: session))
    case .signedIn:
      return session.map { .signedIn(AuthenticatedUser(session: $0)) }
    case .tokenRefreshed:
      return session.map { .refreshed(AuthenticatedUser(session: $0)) }
    case .userUpdated:
      return session.map { .userUpdated(AuthenticatedUser(session: $0)) }
    case .signedOut, .userDeleted:
      return .signedOut
    case .passwordRecovery, .mfaChallengeVerified:
      return nil
    }
  }
}

extension AuthenticatedUser {
  fileprivate init(session: Session) {
    self.init(id: session.user.id, email: session.user.email)
  }
}

/// Translates SDK and transport errors into user-safe failures without copying server text.
enum AuthenticationFailureMapping {
  static func failure(for error: any Error) -> AuthenticationFailure {
    if let failure = error as? AuthenticationFailure {
      return failure
    }

    if let urlError = error as? URLError {
      return mapped(urlError)
    }

    if let authError = error as? AuthError {
      return mapped(authError)
    }

    if let storageError = error as? StorageError {
      return AuthenticationErrorMapper.map(
        errorCode: storageError.error,
        statusCode: storageError.statusCode.flatMap(Int.init)
      )
    }

    if let functionsError = error as? FunctionsError {
      switch functionsError {
      case .httpError(let code, let data):
        // Edge Functions report a stable code in the body, which distinguishes a session that is too
        // old to delete an account from one that has expired, even though both use 403.
        return AuthenticationErrorMapper.map(
          errorCode: edgeFunctionErrorCode(in: data),
          statusCode: code
        )
      case .relayError:
        return .serviceUnavailable
      }
    }

    if let postgrestError = error as? PostgrestError {
      return AuthenticationErrorMapper.map(errorCode: postgrestError.code)
    }

    if error is CancellationError {
      return .appleSignInCancelled
    }

    return AuthenticationErrorMapper.map(errorCode: nil)
  }

  /// Reads `{"error":"<code>"}` from an Edge Function response. Only a short machine-readable code
  /// is accepted, so no server text can reach the interface.
  private static func edgeFunctionErrorCode(in data: Data) -> String? {
    struct EdgeFunctionFailure: Decodable {
      let error: String
    }

    guard let decoded = try? JSONDecoder().decode(EdgeFunctionFailure.self, from: data),
      (1...64).contains(decoded.error.count),
      decoded.error.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_") })
    else {
      return nil
    }
    return decoded.error
  }

  private static func mapped(_ error: URLError) -> AuthenticationFailure {
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
      .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
      .offline
    case .timedOut:
      .timedOut
    case .cancelled:
      .appleSignInCancelled
    default:
      .serviceUnavailable
    }
  }

  private static func mapped(_ error: AuthError) -> AuthenticationFailure {
    switch error {
    case .sessionMissing:
      return .sessionExpired
    case .api(_, let errorCode, _, let response):
      return AuthenticationErrorMapper.map(
        errorCode: errorCode.rawValue,
        statusCode: response.statusCode
      )
    case .pkceGrantCodeExchange(_, _, let code):
      return AuthenticationErrorMapper.map(errorCode: code ?? "pkce_grant_code_exchange")
    case .implicitGrantRedirect:
      return .callbackInvalid
    case .jwtVerificationFailed:
      return .sessionExpired
    default:
      return AuthenticationErrorMapper.map(errorCode: error.errorCode.rawValue)
    }
  }
}
