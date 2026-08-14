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
  /// Built during initialization so the "this scheme is usable" invariant travels with the value
  /// instead of being re-checked, and re-trapped, at every call site.
  let callbackParser: AuthenticationCallbackParser

  /// - Throws: `ConfigurationError.invalidRedirectScheme` when the scheme cannot form a callback.
  init(
    supabaseURL: URL,
    publishableKey: String,
    shareLinkHost: String,
    authRedirectScheme: String,
    appleSignInEnabled: Bool
  ) throws {
    let normalizedScheme = authRedirectScheme.lowercased()
    guard let parser = try? AuthenticationCallbackParser(scheme: normalizedScheme) else {
      throw ConfigurationError.invalidRedirectScheme
    }
    self.supabaseURL = supabaseURL
    self.publishableKey = publishableKey
    self.shareLinkHost = shareLinkHost.lowercased()
    self.authRedirectScheme = normalizedScheme
    self.appleSignInEnabled = appleSignInEnabled
    callbackParser = parser
  }

  static func load(bundle: Bundle = .main) throws -> AppConfiguration {
    try load { key in
      guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }

  /// Reads configuration from any source of trimmed, non-empty strings. Tests supply a dictionary
  /// so the rules can be exercised without a populated `.xcconfig`.
  static func load(value: (String) -> String?) throws -> AppConfiguration {
    guard
      let urlText = value("SUPABASE_URL"),
      let url = URL(string: urlText),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || url.host == "127.0.0.1",
      !urlText.contains("YOUR_PROJECT_REF"),
      let key = value("SUPABASE_PUBLISHABLE_KEY"),
      !key.contains("YOUR_PUBLISHABLE_KEY"),
      // Normalized before the guard so a value such as `Example.Invalid` is recognised as the
      // placeholder it is rather than being stored as one.
      let shareLinkHost = value("SHARE_LINK_HOST")?.lowercased(),
      shareLinkHost != "example.invalid",
      let redirectScheme = value("AUTH_REDIRECT_SCHEME")
    else {
      throw ConfigurationError.missingLocalConfiguration
    }

    let appleFlag = value("APPLE_SIGN_IN_ENABLED")?.lowercased()

    return try AppConfiguration(
      supabaseURL: url,
      publishableKey: key,
      shareLinkHost: shareLinkHost,
      authRedirectScheme: redirectScheme,
      appleSignInEnabled: ["yes", "true", "1"].contains(appleFlag ?? "")
    )
  }

  /// The redirect that must also be allow-listed in Supabase Auth's URL configuration.
  var authCallbackURL: URL {
    callbackParser.callbackURL
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

enum SupabaseClientFactory {
  /// Builds the shared client.
  ///
  /// Session persistence is deliberately left to the SDK: on Apple platforms
  /// `AuthClient.Configuration.defaultLocalStorage` is `KeychainLocalStorage`, and automatic token
  /// refresh is on by default. Adding another store would duplicate the tokens in a less protected
  /// place, so the app keeps only the Keychain copy the SDK already manages.
  ///
  /// `emitLocalSessionAsInitialSession` is on because the app defines an explicit unverified state
  /// for a session it cannot check. With the SDK default the stored session is refreshed before the
  /// initial event, so an offline launch reports no session at all and drops the person on the
  /// sign-in screen. Emitting the cached session instead lets the app's own profile read decide
  /// between the documented offline and expired outcomes.
  static func make(configuration: AppConfiguration) -> SupabaseClient {
    SupabaseClient(
      supabaseURL: configuration.supabaseURL,
      supabaseKey: configuration.publishableKey,
      options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
          redirectToURL: configuration.authCallbackURL,
          flowType: .pkce,
          emitLocalSessionAsInitialSession: true
        )
      )
    )
  }
}
