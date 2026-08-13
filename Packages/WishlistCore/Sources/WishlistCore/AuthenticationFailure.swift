import Foundation

/// User-safe authentication and account failures.
///
/// Cases carry no server text, so a message from the authentication service can never leak an
/// address, token, or database detail into the interface.
public enum AuthenticationFailure: Error, Equatable, Sendable {
  case invalidEmail
  case emailNotAllowed
  case rateLimited
  case linkExpired
  case callbackInvalid
  case appleSignInCancelled
  case appleIdentityTokenMissing
  case appleCredentialRejected
  case appleProviderNotConfigured
  case sessionExpired
  case notSignedIn
  case recentSignInRequired
  case offline
  case timedOut
  case serviceUnavailable
  case unknown

  /// `true` when the person deliberately stopped the flow, so the interface stays quiet.
  public var isCancellation: Bool {
    self == .appleSignInCancelled
  }

  /// `true` when retrying the same request could plausibly succeed.
  public var isRetryable: Bool {
    switch self {
    case .offline, .timedOut, .serviceUnavailable, .rateLimited, .unknown:
      true
    default:
      false
    }
  }

  public var userMessage: String {
    switch self {
    case .invalidEmail:
      "Enter a valid email address."
    case .emailNotAllowed:
      "This address can’t be used to sign in to Jiejie."
    case .rateLimited:
      "Too many sign-in emails were requested. Wait a minute and try again."
    case .linkExpired:
      "That sign-in link has expired. Request a new one."
    case .callbackInvalid:
      "That sign-in link could not be used. Request a new one."
    case .appleSignInCancelled:
      "Sign in with Apple was cancelled."
    case .appleIdentityTokenMissing:
      "Apple did not return an identity token. Try again."
    case .appleCredentialRejected:
      "Apple could not verify this sign-in. Try again."
    case .appleProviderNotConfigured:
      "Sign in with Apple isn’t enabled for this build yet. Use an email link instead."
    case .sessionExpired:
      "Your session expired. Sign in again."
    case .notSignedIn:
      "Sign in to continue."
    case .recentSignInRequired:
      "Sign in again before deleting your account."
    case .offline:
      "You’re offline. Reconnect and try again."
    case .timedOut:
      "The request took too long. Check your connection and try again."
    case .serviceUnavailable:
      "Jiejie can’t reach the service right now. Try again shortly."
    case .unknown:
      "Something went wrong. Try again."
    }
  }
}

/// Maps stable authentication error codes and HTTP status codes to user-safe failures.
public enum AuthenticationErrorMapper {
  public static func map(
    errorCode: String?,
    statusCode: Int? = nil,
    isCancellation: Bool = false,
    isOffline: Bool = false
  ) -> AuthenticationFailure {
    if isCancellation { return .appleSignInCancelled }
    if isOffline { return .offline }

    switch errorCode?.lowercased() {
    case "email_address_invalid", "validation_failed":
      return .invalidEmail
    case "email_address_not_authorized", "email_provider_disabled", "signup_disabled",
      "user_banned":
      return .emailNotAllowed
    case "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit":
      return .rateLimited
    case "otp_expired", "flow_state_expired":
      return .linkExpired
    case "bad_code_verifier", "flow_state_not_found", "bad_json", "bad_jwt", "invalid_jwt",
      "pkce_grant_code_exchange":
      return .callbackInvalid
    case "provider_disabled":
      return .appleProviderNotConfigured
    case "session_not_found", "session_expired", "refresh_token_not_found",
      "refresh_token_already_used":
      return .sessionExpired
    case "no_authorization":
      return .notSignedIn
    case "reauthentication_needed", "recent_sign_in_required":
      return .recentSignInRequired
    case "invalid_credentials", "bad_oauth_state", "bad_oauth_callback":
      return .appleCredentialRejected
    case "request_timeout":
      return .timedOut
    default:
      break
    }

    switch statusCode {
    case 400, 422:
      return .callbackInvalid
    case 401:
      return .notSignedIn
    case 403:
      return .sessionExpired
    case 408:
      return .timedOut
    case 429:
      return .rateLimited
    case 500, 502, 503, 504:
      return .serviceUnavailable
    default:
      return .unknown
    }
  }
}
