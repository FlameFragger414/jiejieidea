import Foundation

/// The lifecycle of a single magic-link email request.
public enum MagicLinkRequestState: Equatable, Sendable {
  case idle
  case sending(EmailAddress)
  case sent(EmailAddress)
  case failed(AuthenticationFailure)

  public var isSending: Bool {
    if case .sending = self { return true }
    return false
  }

  /// `true` only after the authentication server accepted the request. A failed request must never
  /// present this state.
  public var didSend: Bool {
    if case .sent = self { return true }
    return false
  }

  public var failure: AuthenticationFailure? {
    if case .failed(let failure) = self { return failure }
    return nil
  }
}

/// What the caller should do with a submission attempt.
public enum MagicLinkSubmission: Equatable, Sendable {
  /// The address is valid and no request is in flight; send it.
  case send(EmailAddress)
  /// A request for this address is already running; do nothing.
  case alreadyInFlight
  /// The address is not usable; show `issue` beside the field.
  case invalid(ValidationIssue)
}

/// Guards a magic-link request against duplicate submissions and false "email sent" states.
///
/// The state only becomes `.sent` through `markSent()`, which the caller may invoke solely after
/// the authentication server accepted the request.
public struct MagicLinkRequest: Equatable, Sendable {
  public private(set) var state: MagicLinkRequestState

  public init(state: MagicLinkRequestState = .idle) {
    self.state = state
  }

  public var canSubmit: Bool {
    !state.isSending
  }

  public mutating func submit(_ rawEmail: String) -> MagicLinkSubmission {
    if state.isSending {
      return .alreadyInFlight
    }

    do {
      let address = try EmailAddress(rawEmail)
      state = .sending(address)
      return .send(address)
    } catch let issue as ValidationIssue {
      state = .failed(.invalidEmail)
      return .invalid(issue)
    } catch {
      state = .failed(.unknown)
      return .invalid(ValidationIssue(field: "email", message: "Enter a valid email address."))
    }
  }

  public mutating func markSent() {
    guard case .sending(let address) = state else { return }
    state = .sent(address)
  }

  public mutating func markFailed(_ failure: AuthenticationFailure) {
    guard case .sending = state else { return }
    state = .failed(failure)
  }

  /// Called when the in-flight request was cancelled, for example because the screen went away.
  public mutating func markCancelled() {
    guard case .sending = state else { return }
    state = .idle
  }

  /// Clears a completed result so the person can request another link.
  public mutating func reset() {
    guard !state.isSending else { return }
    state = .idle
  }
}
