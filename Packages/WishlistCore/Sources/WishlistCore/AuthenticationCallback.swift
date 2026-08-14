import Foundation

/// The meaningful content of an authentication redirect that the app is willing to forward to the
/// authentication SDK.
public enum AuthenticationCallback: Equatable, Sendable {
  /// A PKCE authorization code that can be exchanged for a session.
  case authorizationCode(String)
  /// The provider reported a failure instead of issuing a code.
  case providerFailure(code: String?)
}

/// Validates authentication redirects before they reach the authentication SDK.
///
/// `DeepLinkParser` decides *which* feature a URL belongs to. This parser decides whether an
/// authentication redirect is well formed enough to act on, so a malformed or unrelated URL is
/// rejected in one place instead of being trusted by every call site.
public struct AuthenticationCallbackParser: Equatable, Sendable {
  /// The custom URL scheme registered by the running build, for example `jiejie-debug`.
  public let scheme: String

  /// The redirect URL that must also be allow-listed in the Supabase dashboard.
  public let callbackURL: URL

  /// - Throws: `ValidationIssue` when the configured scheme is not a usable URL scheme.
  public init(scheme: String) throws {
    let candidate = scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard Self.isValidScheme(candidate),
      let callbackURL = URL(string: "\(candidate)://auth/callback")
    else {
      throw ValidationIssue(
        field: "authRedirectScheme",
        message: "Set AUTH_REDIRECT_SCHEME to a valid URL scheme such as jiejie-debug."
      )
    }
    self.scheme = candidate
    self.callbackURL = callbackURL
  }

  /// Returns the callback content, or `nil` when `url` is not a well-formed callback for this build.
  ///
  /// The parser never logs and never returns the raw parameter values for anything other than the
  /// authorization code, so magic-link secrets are not copied into error paths. Parameter names are
  /// matched exactly, because the Supabase SDK matches them exactly too.
  ///
  /// Any query and fragment content is accepted as input: nothing here can trap, and an unusable
  /// redirect is reported as `nil` rather than crashing the app that was handed it.
  public func parse(_ url: URL) -> AuthenticationCallback? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == scheme,
      components.host?.lowercased() == "auth",
      components.path.split(separator: "/").map(String.init) == ["callback"],
      components.user == nil,
      components.password == nil,
      components.port == nil
    else {
      return nil
    }

    let parameters = Self.parameters(in: components)

    if parameters["error"] != nil || parameters["error_description"] != nil
      || parameters["error_code"] != nil
    {
      return .providerFailure(code: Self.sanitizedErrorCode(parameters))
    }

    guard let code = parameters["code"], Self.isPlausibleAuthorizationCode(code) else {
      return nil
    }
    return .authorizationCode(code)
  }

  /// Supabase sends PKCE parameters in the query string and legacy implicit parameters in the
  /// fragment. Both are inspected so an error reported either way is surfaced rather than ignored.
  ///
  /// The order matches `extractParams` in Supabase's Swift SDK: the fragment is read first and the
  /// query overrides it, so a URL this parser accepts is one the SDK can also complete.
  private static func parameters(in components: URLComponents) -> [String: String] {
    var parameters: [String: String] = [:]

    for source in [components.percentEncodedFragment, components.percentEncodedQuery] {
      guard let source, !source.isEmpty else { continue }
      for (name, value) in FormEncodedParameters.parse(source) {
        parameters[name] = value
      }
    }

    return parameters
  }

  /// Only short, machine-readable provider codes are kept. Free-text descriptions may echo the
  /// address or token from the link, so they are discarded.
  private static func sanitizedErrorCode(_ parameters: [String: String]) -> String? {
    guard let raw = parameters["error_code"] ?? parameters["error"] else { return nil }
    guard (1...64).contains(raw.count),
      raw.allSatisfy({ $0.isLetter && $0.isASCII || $0 == "_" || $0 == "-" })
    else {
      return nil
    }
    return raw.lowercased()
  }

  private static func isPlausibleAuthorizationCode(_ code: String) -> Bool {
    guard (8...512).contains(code.count) else { return false }
    return code.unicodeScalars.allSatisfy { scalar in
      (48...57).contains(scalar.value)
        || (65...90).contains(scalar.value)
        || (97...122).contains(scalar.value)
        || scalar == "-"
        || scalar == "."
        || scalar == "_"
        || scalar == "~"
    }
  }

  private static func isValidScheme(_ scheme: String) -> Bool {
    guard (3...64).contains(scheme.count) else { return false }
    guard let first = scheme.first, first.isLetter, first.isASCII else { return false }
    return scheme.allSatisfy { character in
      character.isASCII && (character.isLetter || character.isNumber || "+-.".contains(character))
    }
  }
}
