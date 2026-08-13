import Foundation

public enum AppRoute: Equatable, Sendable {
  case sharedWishlist(slug: String, token: String?)
  case authenticationCallback(URL)
}

public struct DeepLinkParser: Sendable {
  public let universalLinkHost: String
  public let customScheme: String

  public init(universalLinkHost: String, customScheme: String = "jiejie") {
    self.universalLinkHost = universalLinkHost.lowercased()
    self.customScheme = customScheme.lowercased()
  }

  public func parse(_ url: URL) -> AppRoute? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased()
    else {
      return nil
    }

    if scheme == customScheme,
      components.host?.lowercased() == "auth",
      normalizedPathComponents(components.path) == ["callback"]
    {
      return .authenticationCallback(url)
    }

    let routeComponents: [String]
    if scheme == "https", components.host?.lowercased() == universalLinkHost {
      routeComponents = normalizedPathComponents(components.path)
    } else if scheme == customScheme, components.host?.lowercased() == "w" {
      routeComponents = normalizedPathComponents(components.path)
    } else {
      return nil
    }

    let slug: String
    if scheme == customScheme {
      guard routeComponents.count == 1 else { return nil }
      slug = routeComponents[0]
    } else {
      guard routeComponents.count == 2, routeComponents[0] == "w" else { return nil }
      slug = routeComponents[1]
    }

    guard Self.isValidSlug(slug) else { return nil }
    let token = components.queryItems?
      .first(where: { $0.name == "token" })?
      .value?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard token == nil || Self.isPlausibleShareToken(token!) else { return nil }
    return .sharedWishlist(slug: slug, token: token)
  }

  private func normalizedPathComponents(_ path: String) -> [String] {
    path.split(separator: "/").map(String.init)
  }

  private static func isValidSlug(_ slug: String) -> Bool {
    guard (12...80).contains(slug.count) else { return false }
    return slug.unicodeScalars.allSatisfy { scalar in
      (48...57).contains(Int(scalar.value))
        || (65...90).contains(Int(scalar.value))
        || (97...122).contains(Int(scalar.value))
        || scalar == "-"
        || scalar == "_"
    }
  }

  private static func isPlausibleShareToken(_ token: String) -> Bool {
    guard (32...256).contains(token.count) else { return false }
    return token.unicodeScalars.allSatisfy { scalar in
      (48...57).contains(Int(scalar.value))
        || (65...90).contains(Int(scalar.value))
        || (97...122).contains(Int(scalar.value))
        || scalar == "-"
        || scalar == "_"
    }
  }
}
