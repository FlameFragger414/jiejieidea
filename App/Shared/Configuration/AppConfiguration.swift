import Foundation
import Supabase
import WishlistCore

/// Values supplied by the local `.xcconfig` files and substituted into the generated Info.plist.
///
/// Nothing here is a secret: only the Supabase URL and publishable client key ship in the app. The
/// redirect scheme is read from configuration rather than hard-coded so debug, release, and future
/// enterprise builds can register different schemes without touching call sites.
struct AppConfiguration: Equatable, Sendable {
  let supabaseURL: URL
  let publishableKey: String
  let shareLinkHost: String
  let authRedirectScheme: String
  /// `false` until the Apple Developer capability and the Supabase Apple provider are configured by
  /// hand. The email link flow stays available either way.
  let appleSignInEnabled: Bool

  static func load(bundle: Bundle = .main) throws -> AppConfiguration {
    guard
      let urlText = bundle.string(for: "SUPABASE_URL"),
      let url = URL(string: urlText),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || url.host == "127.0.0.1",
      !urlText.contains("YOUR_PROJECT_REF"),
      let key = bundle.string(for: "SUPABASE_PUBLISHABLE_KEY"),
      !key.contains("YOUR_PUBLISHABLE_KEY"),
      let shareLinkHost = bundle.string(for: "SHARE_LINK_HOST"),
      shareLinkHost != "example.invalid",
      let redirectScheme = bundle.string(for: "AUTH_REDIRECT_SCHEME")
    else {
      throw ConfigurationError.missingLocalConfiguration
    }

    guard (try? AuthenticationCallbackParser(scheme: redirectScheme)) != nil else {
      throw ConfigurationError.invalidRedirectScheme
    }

    return AppConfiguration(
      supabaseURL: url,
      publishableKey: key,
      shareLinkHost: shareLinkHost.lowercased(),
      authRedirectScheme: redirectScheme.lowercased(),
      appleSignInEnabled: bundle.flag(for: "APPLE_SIGN_IN_ENABLED")
    )
  }

  /// The redirect that must also be allow-listed in Supabase Auth's URL configuration.
  var authCallbackURL: URL {
    callbackParser.callbackURL
  }

  var callbackParser: AuthenticationCallbackParser {
    // `load` rejects schemes this initializer cannot accept.
    try! AuthenticationCallbackParser(scheme: authRedirectScheme)
  }

  var deepLinkParser: DeepLinkParser {
    DeepLinkParser(universalLinkHost: shareLinkHost, customScheme: authRedirectScheme)
  }
}

enum ConfigurationError: Error, Equatable {
  case missingLocalConfiguration
  case invalidRedirectScheme

  var userMessage: String {
    switch self {
    case .missingLocalConfiguration:
      "Add your local Supabase configuration to run Jiejie."
    case .invalidRedirectScheme:
      "AUTH_REDIRECT_SCHEME is not a usable URL scheme."
    }
  }
}

extension Bundle {
  fileprivate func string(for key: String) -> String? {
    guard let value = object(forInfoDictionaryKey: key) as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  fileprivate func flag(for key: String) -> Bool {
    guard let value = string(for: key)?.lowercased() else { return false }
    return ["yes", "true", "1"].contains(value)
  }
}

enum SupabaseClientFactory {
  /// Builds the shared client.
  ///
  /// Session persistence is deliberately left to the SDK: on Apple platforms
  /// `AuthClient.Configuration.defaultLocalStorage` is `KeychainLocalStorage`, and automatic token
  /// refresh is on by default. Adding another store would duplicate the tokens in a less protected
  /// place, so the app keeps only the Keychain copy the SDK already manages.
  static func make(configuration: AppConfiguration) -> SupabaseClient {
    SupabaseClient(
      supabaseURL: configuration.supabaseURL,
      supabaseKey: configuration.publishableKey,
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          redirectToURL: configuration.authCallbackURL,
          flowType: .pkce
        )
      )
    )
  }
}
