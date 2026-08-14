import Foundation

/// The explicit confirmation required before a destructive account deletion runs.
public enum AccountDeletionConfirmation {
  /// The word the person must type. Kept short and unambiguous for VoiceOver dictation.
  public static let requiredPhrase = "DELETE"

  public static func matches(_ input: String) -> Bool {
    input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == requiredPhrase
  }
}

/// The lifecycle of an account-deletion request.
public enum AccountDeletionState: Equatable, Sendable {
  case idle
  /// The warning sheet is visible and awaiting confirmation.
  case confirming
  case deleting
  case deleted
  case failed(AuthenticationFailure)

  public var isDeleting: Bool {
    self == .deleting
  }

  public var failure: AuthenticationFailure? {
    if case .failed(let failure) = self { return failure }
    return nil
  }
}

/// What the caller should do with a deletion attempt.
public enum AccountDeletionSubmission: Equatable, Sendable {
  case delete
  case alreadyInFlight
  case confirmationMismatch
}

/// Guards account deletion behind a typed confirmation and against duplicate submissions.
public struct AccountDeletionRequest: Equatable, Sendable {
  public private(set) var state: AccountDeletionState

  public init(state: AccountDeletionState = .idle) {
    self.state = state
  }

  public mutating func beginConfirmation() {
    guard !state.isDeleting, state != .deleted else { return }
    state = .confirming
  }

  public mutating func cancel() {
    guard !state.isDeleting, state != .deleted else { return }
    state = .idle
  }

  public mutating func submit(confirmationText: String) -> AccountDeletionSubmission {
    // A deleted account has nothing left to delete, and re-entering `.deleting` would let the
    // interface issue a second request against an identity that no longer exists.
    if state.isDeleting || state == .deleted {
      return .alreadyInFlight
    }
    guard AccountDeletionConfirmation.matches(confirmationText) else {
      return .confirmationMismatch
    }
    state = .deleting
    return .delete
  }

  public mutating func markDeleted() {
    guard state.isDeleting else { return }
    state = .deleted
  }

  public mutating func markFailed(_ failure: AuthenticationFailure) {
    guard state.isDeleting else { return }
    state = .failed(failure)
  }
}
