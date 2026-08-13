import Foundation

/// A field-level validation failure suitable for display next to an input.
public struct ValidationIssue: Error, Equatable, Sendable {
  public let field: String
  public let message: String

  public init(field: String, message: String) {
    self.field = field
    self.message = message
  }
}

/// User-safe failures shared across presentation layers.
public enum WishlistError: Error, Equatable, Sendable {
  case authenticationRequired
  case accessDenied
  case itemUnavailable
  case insufficientQuantity
  case reservationNotFound
  case reservationNotActive
  case idempotencyConflict
  case invalidInput(String)
  case offline
  case timedOut
  case serviceUnavailable
  case unknown

  public var userMessage: String {
    switch self {
    case .authenticationRequired:
      "Sign in to continue."
    case .accessDenied:
      "You no longer have access to this wishlist."
    case .itemUnavailable:
      "This gift is no longer available."
    case .insufficientQuantity:
      "That quantity is no longer available. Refresh the wishlist and try again."
    case .reservationNotFound:
      "This reservation could not be found."
    case .reservationNotActive:
      "This reservation is no longer active."
    case .idempotencyConflict:
      "This request conflicts with an earlier reservation attempt. Refresh before trying again."
    case .invalidInput(let message):
      message
    case .offline:
      "You’re offline. Reservations need a connection before they can be confirmed."
    case .timedOut:
      "The request took too long. Check your connection and try again."
    case .serviceUnavailable:
      "Jiejie can’t reach the service right now. Try again shortly."
    case .unknown:
      "Something went wrong. Try again."
    }
  }
}

/// Maps stable server error codes to copy that does not leak database details.
public enum BackendErrorMapper {
  public static func map(code: String?, isOffline: Bool = false) -> WishlistError {
    if isOffline {
      return .offline
    }

    switch code?.lowercased() {
    case "authentication_required", "28000", "401":
      return .authenticationRequired
    case "wishlist_access_denied", "42501", "403":
      return .accessDenied
    case "wishlist_item_unavailable":
      return .itemUnavailable
    case "insufficient_quantity":
      return .insufficientQuantity
    case "reservation_not_found":
      return .reservationNotFound
    case "reservation_not_active":
      return .reservationNotActive
    case "idempotency_conflict", "23505":
      return .idempotencyConflict
    case "57014", "timeout":
      return .timedOut
    case "502", "503", "504", "service_unavailable":
      return .serviceUnavailable
    default:
      return .unknown
    }
  }
}
