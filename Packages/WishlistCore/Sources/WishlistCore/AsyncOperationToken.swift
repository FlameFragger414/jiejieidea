import Foundation

/// A monotonic counter that lets a view model discard results from superseded async work.
///
/// SwiftUI tasks are cancelled and restarted freely, so a slower earlier request can finish after a
/// newer one. Comparing tokens makes "ignore the stale answer" an explicit, tested rule rather than
/// an accident of ordering.
public struct AsyncOperationToken: Equatable, Hashable, Sendable, Comparable {
  private let value: UInt64

  fileprivate init(value: UInt64) {
    self.value = value
  }

  public static func < (lhs: AsyncOperationToken, rhs: AsyncOperationToken) -> Bool {
    lhs.value < rhs.value
  }
}

/// Issues `AsyncOperationToken` values and reports whether a token is still the newest one.
public struct AsyncOperationSequence: Equatable, Sendable {
  private var latest: UInt64 = 0

  public init() {}

  /// Starts a new operation and invalidates every token issued earlier.
  public mutating func start() -> AsyncOperationToken {
    latest += 1
    return AsyncOperationToken(value: latest)
  }

  /// `true` when `token` came from the most recent `start()`.
  public func isCurrent(_ token: AsyncOperationToken) -> Bool {
    token == AsyncOperationToken(value: latest)
  }

  /// Invalidates every outstanding token, for example after sign-out.
  public mutating func cancelAll() {
    latest += 1
  }
}
