import Foundation
import WishlistCore
import XCTest

final class AppConfigurationTests: XCTestCase {
  private var validValues: [String: String] {
    [
      "SUPABASE_URL": "https://project.example.invalid",
      "SUPABASE_PUBLISHABLE_KEY": "publishable-test-key",
      "SHARE_LINK_HOST": "Gifts.Example.Invalid",
      "AUTH_REDIRECT_SCHEME": "jiejie-debug",
      "APPLE_SIGN_IN_ENABLED": "NO",
    ]
  }

  private func load(_ values: [String: String]) throws -> AppConfiguration {
    try AppConfiguration.load { key in
      guard let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      else {
        return nil
      }
      return value
    }
  }

  func testLoadsEveryValueAndDerivesTheCallbackURL() throws {
    let configuration = try load(validValues)

    XCTAssertEqual(configuration.shareLinkHost, "gifts.example.invalid")
    XCTAssertEqual(configuration.authRedirectScheme, "jiejie-debug")
    XCTAssertFalse(configuration.appleSignInEnabled)
    XCTAssertEqual(configuration.authCallbackURL.absoluteString, "jiejie-debug://auth/callback")
  }

  func testAppleSignInIsOptInOnly() throws {
    var values = validValues
    values["APPLE_SIGN_IN_ENABLED"] = "YES"
    XCTAssertTrue(try load(values).appleSignInEnabled)

    values["APPLE_SIGN_IN_ENABLED"] = ""
    XCTAssertFalse(try load(values).appleSignInEnabled)

    values.removeValue(forKey: "APPLE_SIGN_IN_ENABLED")
    XCTAssertFalse(try load(values).appleSignInEnabled)
  }

  func testPlaceholderValuesAreTreatedAsMissing() {
    let placeholders = [
      "SUPABASE_URL": "https://YOUR_PROJECT_REF.supabase.co",
      "SUPABASE_PUBLISHABLE_KEY": "YOUR_PUBLISHABLE_KEY",
      "SHARE_LINK_HOST": "example.invalid",
    ]

    for (key, placeholder) in placeholders {
      var values = validValues
      values[key] = placeholder
      XCTAssertThrowsError(try load(values)) { error in
        XCTAssertEqual(error as? ConfigurationError, .missingLocalConfiguration, "for \(key)")
      }
    }
  }

  func testAMissingKeyIsReportedRatherThanCrashing() {
    for key in validValues.keys where key != "APPLE_SIGN_IN_ENABLED" {
      var values = validValues
      values.removeValue(forKey: key)
      XCTAssertThrowsError(try load(values)) { error in
        XCTAssertEqual(error as? ConfigurationError, .missingLocalConfiguration, "missing \(key)")
      }
    }
  }

  func testOnlyHTTPSOrTheLocalStackIsAccepted() throws {
    var values = validValues
    values["SUPABASE_URL"] = "http://project.example.invalid"
    XCTAssertThrowsError(try load(values))

    values["SUPABASE_URL"] = "http://127.0.0.1:54321"
    XCTAssertNoThrow(try load(values))
  }

  func testAnUnusableRedirectSchemeIsReported() {
    for scheme in ["1jiejie", "jiejie debug", "ab"] {
      var values = validValues
      values["AUTH_REDIRECT_SCHEME"] = scheme
      XCTAssertThrowsError(try load(values)) { error in
        XCTAssertEqual(error as? ConfigurationError, .invalidRedirectScheme, "scheme \(scheme)")
      }
    }
  }

  /// The scheme the parser is built from is the normalized one, so the two can never disagree.
  func testTheRedirectSchemeIsNormalizedBeforeItIsUsed() throws {
    var values = validValues
    values["AUTH_REDIRECT_SCHEME"] = "Jiejie-Debug"
    let configuration = try load(values)

    XCTAssertEqual(configuration.authRedirectScheme, "jiejie-debug")
    XCTAssertEqual(configuration.authCallbackURL.absoluteString, "jiejie-debug://auth/callback")
    XCTAssertEqual(configuration.callbackParser.scheme, "jiejie-debug")
  }

  /// A configuration value cannot be built from a scheme that would later trap when a callback URL
  /// is derived from it.
  func testAConfigurationCannotBeBuiltWithAnUnusableScheme() {
    XCTAssertThrowsError(
      try AppConfiguration(
        supabaseURL: URL(string: "https://project.example.invalid")!,
        publishableKey: "publishable-test-key",
        shareLinkHost: "gifts.example.invalid",
        authRedirectScheme: "not a scheme",
        appleSignInEnabled: false
      )
    ) { error in
      XCTAssertEqual(error as? ConfigurationError, .invalidRedirectScheme)
    }
  }

  func testTheDeepLinkRouterUsesTheConfiguredSchemeAndHost() throws {
    let parser = try load(validValues).deepLinkParser

    let callback = URL(string: "jiejie-debug://auth/callback?code=abcdefgh12345678")!
    XCTAssertEqual(parser.parse(callback), .authenticationCallback(callback))
    XCTAssertNil(parser.parse(URL(string: "jiejie://auth/callback?code=abcdefgh12345678")!))
  }
}
