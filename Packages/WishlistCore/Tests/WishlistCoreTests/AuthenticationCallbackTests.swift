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
