import Foundation

/// A syntactically valid, normalized email address.
///
/// Validation happens before any network request so the sign-in screen can report a problem
/// without contacting the authentication server.
public struct EmailAddress: Equatable, Hashable, Sendable {
  /// The trimmed, lowercased address suitable for submission.
  public let normalized: String

  public init(_ raw: String) throws {
    let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard Self.isValidNormalizedAddress(candidate) else {
      throw ValidationIssue(field: "email", message: "Enter a valid email address.")
    }
    normalized = candidate
  }

  /// The part after the `@`, useful for showing "check your inbox" copy.
  public var domain: String {
    // `init` guarantees a single `@` with a non-empty domain, but reading the value positionally
    // would turn a later change to that rule into a crash.
    normalized.split(separator: "@").last.map(String.init) ?? ""
  }

  public static func isValid(_ raw: String) -> Bool {
    (try? EmailAddress(raw)) != nil
  }

  private static func isValidNormalizedAddress(_ candidate: String) -> Bool {
    guard (6...254).contains(candidate.count) else { return false }
    guard !candidate.unicodeScalars.contains(where: isDisallowedScalar) else { return false }

    let parts = candidate.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    return isValidLocalPart(parts[0]) && isValidDomain(parts[1])
  }

  private static func isDisallowedScalar(_ scalar: Unicode.Scalar) -> Bool {
    CharacterSet.whitespacesAndNewlines.contains(scalar)
      || CharacterSet.controlCharacters.contains(scalar)
      || scalar.value > 127
  }

  private static func isValidLocalPart(_ localPart: Substring) -> Bool {
    guard (1...64).contains(localPart.count) else { return false }
    guard !localPart.hasPrefix("."), !localPart.hasSuffix("."), !localPart.contains("..") else {
      return false
    }
    let allowedSymbols = Set("!#$%&'*+-/=?^_`{|}~.")
    return localPart.allSatisfy { character in
      character.isASCIILetterOrDigit || allowedSymbols.contains(character)
    }
  }

  private static func isValidDomain(_ domain: Substring) -> Bool {
    guard (4...253).contains(domain.count) else { return false }
    let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else { return false }

    for label in labels {
      guard (1...63).contains(label.count) else { return false }
      guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
      guard label.allSatisfy({ $0.isASCIILetterOrDigit || $0 == "-" }) else { return false }
    }

    guard let topLevel = labels.last, topLevel.count >= 2 else { return false }
    return topLevel.allSatisfy(\.isASCIILetter)
  }
}

extension Character {
  fileprivate var isASCIILetter: Bool {
    guard let ascii = asciiValue else { return false }
    return (65...90).contains(ascii) || (97...122).contains(ascii)
  }

  fileprivate var isASCIILetterOrDigit: Bool {
    guard let ascii = asciiValue else { return false }
    return isASCIILetter || (48...57).contains(ascii)
  }
}
