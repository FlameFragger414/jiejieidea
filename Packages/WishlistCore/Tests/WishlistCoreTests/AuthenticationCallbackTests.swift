import Foundation
import XCTest

@testable import WishlistCore

final class AuthenticationCallbackTests: XCTestCase {
  private let parser = try! AuthenticationCallbackParser(scheme: "jiejie-debug")

  func testCallbackURLMatchesConfiguredScheme() {
    XCTAssertEqual(parser.callbackURL.absoluteString, "jiejie-debug://auth/callback")
  }

  func testParsesPKCEAuthorizationCode() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback?code=6f0a1b2c-3d4e-5f60-7182-93a4b5c6d7e8"))
    XCTAssertEqual(
      parser.parse(url),
      .authorizationCode("6f0a1b2c-3d4e-5f60-7182-93a4b5c6d7e8")
    )
  }

  func testAcceptsUppercaseSchemeFromSystem() throws {
    let url = try XCTUnwrap(URL(string: "JIEJIE-DEBUG://auth/callback?code=abcdefgh12345678"))
    XCTAssertEqual(parser.parse(url), .authorizationCode("abcdefgh12345678"))
  }

  func testRejectsUnrelatedScheme() throws {
    let url = try XCTUnwrap(URL(string: "jiejie://auth/callback?code=abcdefgh12345678"))
    XCTAssertNil(parser.parse(url))
  }

  func testRejectsUniversalLinkAndWrongHost() throws {
    let https = try XCTUnwrap(URL(string: "https://auth/callback?code=abcdefgh12345678"))
    let wrongHost = try XCTUnwrap(
      URL(string: "jiejie-debug://authorize/callback?code=abcdefgh12345678"))
    XCTAssertNil(parser.parse(https))
    XCTAssertNil(parser.parse(wrongHost))
  }

  func testRejectsWrongOrExtraPath() throws {
    let wrongPath = try XCTUnwrap(URL(string: "jiejie-debug://auth/session?code=abcdefgh12345678"))
    let extraPath = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback/extra?code=abcdefgh12345678"))
    XCTAssertNil(parser.parse(wrongPath))
    XCTAssertNil(parser.parse(extraPath))
  }

  func testRejectsEmbeddedCredentialsAndPort() throws {
    let credentials = try XCTUnwrap(
      URL(string: "jiejie-debug://attacker@auth/callback?code=abcdefgh12345678"))
    let port = try XCTUnwrap(URL(string: "jiejie-debug://auth:8080/callback?code=abcdefgh12345678"))
    XCTAssertNil(parser.parse(credentials))
    XCTAssertNil(parser.parse(port))
  }

  func testRejectsMissingCodeAndImplausibleCode() throws {
    let noCode = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback"))
    let shortCode = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback?code=abc"))
    let injectedCode = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback?code=abcdefgh12345678%20or%201=1"))
    XCTAssertNil(parser.parse(noCode))
    XCTAssertNil(parser.parse(shortCode))
    XCTAssertNil(parser.parse(injectedCode))
  }

  func testReportsProviderFailureFromQuery() throws {
    let url = try XCTUnwrap(
      URL(
        string:
          "jiejie-debug://auth/callback?error=access_denied&error_code=otp_expired&error_description=Email%20link%20is%20invalid%20or%20has%20expired"
      ))
    XCTAssertEqual(parser.parse(url), .providerFailure(code: "otp_expired"))
  }

  func testReportsProviderFailureFromFragment() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback#error=access_denied&error_code=otp_expired"))
    XCTAssertEqual(parser.parse(url), .providerFailure(code: "otp_expired"))
  }

  // MARK: - Percent-encoded and malformed callback content

  /// The redirect Supabase actually sends for an expired link. Reading the decoded fragment and
  /// assigning it back as a percent-encoded query used to trap here.
  func testAnEncodedSpaceInTheFragmentIsParsedInsteadOfTrapping() throws {
    let url = try XCTUnwrap(
      URL(
        string:
          "jiejie-debug://auth/callback#error=access_denied&error_code=otp_expired&error_description=Email%20link%20is%20invalid%20or%20has%20expired"
      ))
    XCTAssertEqual(parser.parse(url), .providerFailure(code: "otp_expired"))
  }

  func testAnEncodedPercentSignInTheFragmentIsParsed() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback#error_code=otp_expired&error_description=100%25"))
    XCTAssertEqual(parser.parse(url), .providerFailure(code: "otp_expired"))
  }

  func testAMalformedEscapeInTheFragmentIsSurvived() throws {
    let malformed = [
      "jiejie-debug://auth/callback#error_code=otp_expired&error_description=%zz",
      "jiejie-debug://auth/callback#error_code=otp_expired&error_description=%",
      "jiejie-debug://auth/callback#error_code=otp_expired&error_description=%2",
      "jiejie-debug://auth/callback#error_code=otp_expired&error_description=a%%20b",
    ]
    var exercised = 0
    for raw in malformed {
      guard let url = URL(string: raw) else { continue }
      exercised += 1
      XCTAssertEqual(parser.parse(url), .providerFailure(code: "otp_expired"), raw)
    }
    XCTAssertGreaterThan(exercised, 0, "no malformed fragment reached the parser")
  }

  func testAMalformedEscapeAroundTheCodeIsRejectedRatherThanDecoded() throws {
    let url = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback?code=abcdefgh1234%zz5678"))
    XCTAssertNil(parser.parse(url))
  }

  func testAPlusIsDecodedAsASpaceLikeTheSDKDoes() throws {
    let url = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback?code=abcdefgh+12345678"))
    XCTAssertNil(parser.parse(url))
  }

  func testAFieldWithoutAValueIsIgnored() throws {
    let noValue = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback?code"))
    let emptyValue = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback?code="))
    XCTAssertNil(parser.parse(noValue))
    XCTAssertNil(parser.parse(emptyValue))
  }

  /// Supabase keeps the last occurrence of a repeated field, so a callback this parser accepts is
  /// exchanged for the same code the SDK reads.
  func testARepeatedFieldKeepsTheLastValue() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback?code=aaaaaaaa11111111&code=bbbbbbbb22222222"))
    XCTAssertEqual(parser.parse(url), .authorizationCode("bbbbbbbb22222222"))
  }

  /// Supabase reads the fragment first and lets the query override it. A fragment that disagreed
  /// with the query would otherwise let this parser approve a code the SDK never exchanges.
  func testTheQueryOverridesTheFragmentAsTheSDKDoes() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback?code=aaaaaaaa11111111#code=bbbbbbbb22222222"))
    XCTAssertEqual(parser.parse(url), .authorizationCode("aaaaaaaa11111111"))
  }

  func testAValueContainingAnEqualsSignIsKeptWhole() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback#error_code=otp_expired&state=abc%3Ddef"))
    XCTAssertEqual(parser.parse(url), .providerFailure(code: "otp_expired"))
  }

  func testAnUppercaseParameterNameIsNotTreatedAsACode() throws {
    let url = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback?CODE=abcdefgh12345678"))
    XCTAssertNil(parser.parse(url))
  }

  /// Arbitrary bytes reach this parser from any app that can open the scheme, so no input may trap.
  /// The generator is seeded, so a failure reproduces exactly.
  func testArbitraryQueryAndFragmentContentNeverTraps() throws {
    var generator = SeededGenerator(seed: 0x5EED_1234_ABCD_0001)
    let alphabet = Array("abcABC019 %&=+#?/:@[]\\\"'<>{}|^~`;,.-_$*!()\n\t\u{7F}é中🎁")

    var exercised = 0
    for iteration in 0..<2_000 {
      let length = Int.random(in: 0...48, using: &generator)
      let noise = String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
      let separator = iteration.isMultiple(of: 2) ? "?" : "#"
      guard let url = URL(string: "jiejie-debug://auth/callback\(separator)\(noise)") else {
        continue
      }
      exercised += 1

      switch parser.parse(url) {
      case .authorizationCode(let code):
        XCTAssertTrue(
          (8...512).contains(code.count),
          "accepted an implausible code from \(noise)"
        )
      case .providerFailure(let code):
        if let code {
          XCTAssertTrue(
            (1...64).contains(code.count),
            "accepted an implausible error code from \(noise)"
          )
        }
      case nil:
        break
      }
    }
    XCTAssertGreaterThan(exercised, 500, "too few generated redirects reached the parser")
  }

  func testEveryDeepLinkFixtureIsSurvivedByTheCallbackParser() throws {
    let hostile = [
      "jiejie-debug://auth/callback?#",
      "jiejie-debug://auth/callback?&&&",
      "jiejie-debug://auth/callback#=",
      "jiejie-debug://auth/callback#===",
      "jiejie-debug://auth/callback#%",
      "jiejie-debug://auth/callback?%25=%25#%25=%25",
      "jiejie-debug://auth/callback#code=%00%01%02",
    ]
    for raw in hostile {
      guard let url = URL(string: raw) else { continue }
      XCTAssertNil(parser.parse(url), raw)
    }
  }

  func testDiscardsUnsafeErrorCodeText() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback?error_code=mia.chen%40example.invalid"))
    XCTAssertEqual(parser.parse(url), .providerFailure(code: nil))
  }

  func testFailureTakesPrecedenceOverCode() throws {
    let url = try XCTUnwrap(
      URL(string: "jiejie-debug://auth/callback?code=abcdefgh12345678&error_code=otp_expired"))
    XCTAssertEqual(parser.parse(url), .providerFailure(code: "otp_expired"))
  }

  func testRejectsUnusableConfiguredScheme() {
    XCTAssertThrowsError(try AuthenticationCallbackParser(scheme: ""))
    XCTAssertThrowsError(try AuthenticationCallbackParser(scheme: "1jiejie"))
    XCTAssertThrowsError(try AuthenticationCallbackParser(scheme: "jiejie debug"))
  }

  func testDeepLinkRouterAgreesWithConfiguredScheme() throws {
    let router = DeepLinkParser(
      universalLinkHost: "gifts.example.com", customScheme: "jiejie-debug")
    let url = try XCTUnwrap(URL(string: "jiejie-debug://auth/callback?code=abcdefgh12345678"))
    XCTAssertEqual(router.parse(url), .authenticationCallback(url))
  }
}

/// A deterministic generator, so a fuzz failure reproduces from the seed recorded in the test.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
  }

  mutating func next() -> UInt64 {
    state ^= state >> 12
    state ^= state << 25
    state ^= state >> 27
    return state &* 2_685_821_657_736_338_717
  }
}
