import AuthenticationServices
import Foundation
import WishlistCore

/// The Sendable result of a native Sign in with Apple attempt.
enum AppleSignInOutcome: Sendable {
  case credential(AppleIdentityCredential)
  case failure(AuthenticationFailure)
}

/// Holds the nonce between `onRequest` and `onCompletion` of a single authorization.
///
/// `ASAuthorizationController` needs the SHA-256 digest before it starts and Supabase needs the raw
/// value afterwards. The value is taken exactly once so a replayed credential cannot be verified
/// against a nonce that was already used.
final class AppleSignInNonceStore: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: SignInWithAppleNonce?

  /// Generates a nonce and returns the digest to place on the request, or `nil` if generation
  /// failed, in which case the request must not proceed.
  func prepare() -> String? {
    guard let nonce = try? SignInWithAppleNonce() else { return nil }
    lock.lock()
    defer { lock.unlock() }
    pending = nonce
    return nonce.hashed
  }

  func outcome(for result: Result<ASAuthorization, any Error>) -> AppleSignInOutcome {
    lock.lock()
    let nonce = pending
    pending = nil
    lock.unlock()

    switch result {
    case .success(let authorization):
      guard let nonce else {
        return .failure(.appleCredentialRejected)
      }
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
        return .failure(.appleCredentialRejected)
      }

      let identityToken = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
      do {
        return .credential(
          try AppleIdentityCredential(
            identityToken: identityToken,
            nonce: nonce,
            fullName: credential.fullName?.formatted()
          )
        )
      } catch let failure as AuthenticationFailure {
        return .failure(failure)
      } catch {
        return .failure(.appleCredentialRejected)
      }

    case .failure(let error):
      return .failure(AppleSignInFailureMapping.failure(for: error))
    }
  }

  func discard() {
    lock.lock()
    pending = nil
    lock.unlock()
  }
}

enum AppleSignInFailureMapping {
  static func failure(for error: any Error) -> AuthenticationFailure {
    if let authorizationError = error as? ASAuthorizationError {
      switch authorizationError.code {
      case .canceled:
        return .appleSignInCancelled
      case .failed, .invalidResponse, .notHandled:
        return .appleCredentialRejected
      case .unknown:
        return .unknown
      default:
        return .unknown
      }
    }

    if let urlError = error as? URLError {
      return urlError.code == .notConnectedToInternet ? .offline : .serviceUnavailable
    }

    if error is CancellationError {
      return .appleSignInCancelled
    }

    return .unknown
  }
}
