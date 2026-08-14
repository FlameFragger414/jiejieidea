import Foundation
import XCTest

@testable import WishlistCore

/// A deterministic generator so nonce generation can be asserted without relying on randomness.
private struct CountingGenerator: RandomNumberGenerator {
  private var counter: UInt64 = 0

  mutating func next() -> UInt64 {
    counter += 1
    return counter
  }
}

final class SignInWithAppleNonceTests: XCTestCase {
  func testGeneratesRequestedLengthFromAllowedCharacters() throws {
    var generator = CountingGenerator()
    let nonce = try SignInWithAppleNonce(length: 64, using: &generator)
    XCTAssertEqual(nonce.raw.count, 64)
    XCTAssertTrue(nonce.raw.allSatisfy(SignInWithAppleNonce.allowedCharacters.contains))
  }

  func testSystemGeneratedNoncesAreDistinct() throws {
    let first = try SignInWithAppleNonce()
    let second = try SignInWithAppleNonce()
    XCTAssertEqual(first.raw.count, 32)
    XCTAssertNotEqual(first.raw, second.raw)
    XCTAssertNotEqual(first.hashed, second.hashed)
  }

  func testHashedValueIsTheSHA256HexOfTheRawValue() throws {
    let nonce = try SignInWithAppleNonce(raw: String(repeating: "a", count: 32))
    XCTAssertEqual(
      nonce.hashed,
      "3ba3f5f43b92602683c19aee62a20342b084dd5971ddd33808d81a328879a547"
    )
    XCTAssertEqual(nonce.hashed.count, 64)
  }

  func testRejectsShortOrIllegalNonces() {
    XCTAssertThrowsError(try SignInWithAppleNonce(raw: "short"))
    XCTAssertThrowsError(try SignInWithAppleNonce(raw: String(repeating: "a", count: 31)))
    XCTAssertThrowsError(try SignInWithAppleNonce(raw: String(repeating: "!", count: 32)))
    XCTAssertThrowsError(try SignInWithAppleNonce(raw: String(repeating: "a", count: 257)))
  }

  func testRejectsUnsupportedGeneratedLength() {
    var generator = CountingGenerator()
    XCTAssertThrowsError(try SignInWithAppleNonce(length: 8, using: &generator))
    XCTAssertThrowsError(try SignInWithAppleNonce(length: 512, using: &generator))
  }

  func testAPreparedNonceIsUsableUntilItExpires() {
    let prepared = Date(timeIntervalSince1970: 1_700_000_000)
    let validity = SignInWithAppleNonceFreshness.validity

    XCTAssertTrue(
      SignInWithAppleNonceFreshness.isUsable(preparedAt: prepared, now: prepared))
    XCTAssertTrue(
      SignInWithAppleNonceFreshness.isUsable(
        preparedAt: prepared, now: prepared.addingTimeInterval(validity)))
    XCTAssertFalse(
      SignInWithAppleNonceFreshness.isUsable(
        preparedAt: prepared, now: prepared.addingTimeInterval(validity + 1)))
  }

  /// A clock that moved backwards makes the age negative. That is refused rather than read as an
  /// unusually fresh nonce.
  func testANonceFromTheFutureIsNotUsable() {
    let prepared = Date(timeIntervalSince1970: 1_700_000_000)
    XCTAssertFalse(
      SignInWithAppleNonceFreshness.isUsable(
        preparedAt: prepared, now: prepared.addingTimeInterval(-1)))
  }

  func testCredentialRequiresAnIdentityToken() throws {
    let nonce = try SignInWithAppleNonce(raw: String(repeating: "b", count: 32))
    XCTAssertThrowsError(try AppleIdentityCredential(identityToken: nil, nonce: nonce)) { error in
      XCTAssertEqual(error as? AuthenticationFailure, .appleIdentityTokenMissing)
    }
    XCTAssertThrowsError(try AppleIdentityCredential(identityToken: "", nonce: nonce)) { error in
      XCTAssertEqual(error as? AuthenticationFailure, .appleIdentityTokenMissing)
    }
  }

  func testCredentialRejectsTokensThatAreNotJWTs() throws {
    let nonce = try SignInWithAppleNonce(raw: String(repeating: "b", count: 32))
    for token in ["not-a-jwt", "only.two", "a..c", "hea der.payload.signature"] {
      XCTAssertThrowsError(try AppleIdentityCredential(identityToken: token, nonce: nonce)) {
        error in
        XCTAssertEqual(error as? AuthenticationFailure, .appleCredentialRejected)
      }
    }
  }

  func testCredentialKeepsNonceAndTrimsOptionalName() throws {
    let nonce = try SignInWithAppleNonce(raw: String(repeating: "b", count: 32))
    let credential = try AppleIdentityCredential(
      identityToken: "header.payload.signature",
      nonce: nonce,
      fullName: "  Mia Chen  "
    )
    XCTAssertEqual(credential.nonce, nonce)
    XCTAssertEqual(credential.fullName, "Mia Chen")

    let anonymous = try AppleIdentityCredential(
      identityToken: "header.payload.signature",
      nonce: nonce,
      fullName: "   "
    )
    XCTAssertNil(anonymous.fullName)
  }
}
