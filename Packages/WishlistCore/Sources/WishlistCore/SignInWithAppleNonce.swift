import Foundation

/// A single-use nonce pair for the native Sign in with Apple flow.
///
/// Apple signs the SHA-256 digest into the identity token, while Supabase needs the original value
/// to verify that digest. Generating both together keeps the two from drifting apart, and the type
/// is single-use so a replayed credential cannot be paired with a fresh nonce.
public struct SignInWithAppleNonce: Equatable, Sendable {
  /// The value sent to Supabase alongside the identity token.
  public let raw: String
  /// The value assigned to `ASAuthorizationAppleIDRequest.nonce`.
  public let hashed: String

  /// Characters Apple accepts in a nonce, and which survive URL and JSON transport unchanged.
  static let allowedCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._")
  static let minimumLength = 32
  static let maximumLength = 256

  /// Creates a nonce from cryptographically secure random bytes.
  ///
  /// - Parameters:
  ///   - length: Number of nonce characters. Apple's guidance is at least 32.
  ///   - generator: Injected for deterministic tests; production uses the system generator, which
  ///     is cryptographically secure on Apple platforms.
  public init<Generator: RandomNumberGenerator>(
    length: Int = 32,
    using generator: inout Generator
  ) throws {
    guard (Self.minimumLength...Self.maximumLength).contains(length) else {
      throw ValidationIssue(
        field: "nonce",
        message: "A Sign in with Apple nonce needs between 32 and 256 characters."
      )
    }

    var value = ""
    value.reserveCapacity(length)
    for _ in 0..<length {
      let index = Int(generator.next(upperBound: UInt64(Self.allowedCharacters.count)))
      value.append(Self.allowedCharacters[index])
    }

    try self.init(raw: value)
  }

  public init() throws {
    var generator = SystemRandomNumberGenerator()
    try self.init(length: 32, using: &generator)
  }

  /// Rebuilds a nonce pair from a previously generated raw value.
  public init(raw: String) throws {
    guard (Self.minimumLength...Self.maximumLength).contains(raw.count),
      raw.allSatisfy(Self.allowedCharacters.contains)
    else {
      throw ValidationIssue(
        field: "nonce",
        message: "A Sign in with Apple nonce needs between 32 and 256 unreserved characters."
      )
    }

    self.raw = raw
    hashed = SHA256Digest.hexadecimal(of: raw)
  }
}

/// The result of a native Sign in with Apple attempt, reduced to what Supabase needs.
public struct AppleIdentityCredential: Equatable, Sendable {
  public let identityToken: String
  public let nonce: SignInWithAppleNonce
  /// Apple supplies a name only on the very first authorization, so it is optional.
  public let fullName: String?

  /// - Throws: `AuthenticationFailure.appleIdentityTokenMissing` when Apple returned an
  ///   authorization without a usable identity token, and
  ///   `AuthenticationFailure.appleCredentialRejected` when the token is not a JWT.
  public init(
    identityToken: String?,
    nonce: SignInWithAppleNonce,
    fullName: String? = nil
  ) throws {
    guard let identityToken, !identityToken.isEmpty else {
      throw AuthenticationFailure.appleIdentityTokenMissing
    }
    guard Self.looksLikeJWT(identityToken) else {
      throw AuthenticationFailure.appleCredentialRejected
    }

    self.identityToken = identityToken
    self.nonce = nonce
    self.fullName = fullName?.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty
  }

  /// A cheap shape check. Signature and claim verification happen server-side in Supabase; this
  /// only stops obviously malformed input from being sent.
  private static func looksLikeJWT(_ token: String) -> Bool {
    let segments = token.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3 else { return false }
    return segments.allSatisfy { segment in
      !segment.isEmpty
        && segment.allSatisfy { character in
          character.isASCII
            && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }
  }
}

extension String {
  fileprivate var nilWhenEmpty: String? { isEmpty ? nil : self }
}
