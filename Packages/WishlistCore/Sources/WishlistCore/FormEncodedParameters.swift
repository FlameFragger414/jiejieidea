import Foundation

/// Reads `application/x-www-form-urlencoded` pairs out of a raw percent-encoded query or fragment.
///
/// `URLComponents` cannot be used for this. Its `fragment` accessor returns already-decoded text,
/// and assigning decoded text back to `percentEncodedQuery` traps on ordinary redirect content such
/// as an encoded space. Decoding each component here instead means arbitrary callback input — a
/// stray `%`, a truncated escape, a repeated field — produces a value or is skipped, never a crash.
///
/// The rules deliberately mirror `extractParams` in Supabase's Swift SDK, so this parser accepts
/// exactly the redirects that SDK can act on:
///
/// - pairs are separated by `&` and split on the first `=`;
/// - a pair without a `=`, or with an empty value, is skipped;
/// - `+` decodes to a space before percent decoding;
/// - a component whose percent escapes are malformed keeps its raw text; and
/// - a repeated field keeps the last value.
enum FormEncodedParameters {
  static func parse(_ percentEncoded: some StringProtocol) -> [(name: String, value: String)] {
    percentEncoded
      .split(separator: "&")
      .compactMap { pair in
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        return (decoded(parts[0]), decoded(parts[1]))
      }
  }

  private static func decoded(_ component: some StringProtocol) -> String {
    let plusDecoded = component.replacingOccurrences(of: "+", with: " ")
    return plusDecoded.removingPercentEncoding ?? plusDecoded
  }
}
