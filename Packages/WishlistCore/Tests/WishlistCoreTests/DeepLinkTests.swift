import Foundation
import XCTest

@testable import WishlistCore

final class DeepLinkTests: XCTestCase {
  private let parser = DeepLinkParser(universalLinkHost: "gifts.example.com")
  private let slug = "abcdef0123456789abcdef01"
  private let token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  func testParsesUniversalShareLink() throws {
    let url = try XCTUnwrap(URL(string: "https://gifts.example.com/w/\(slug)?token=\(token)"))
    XCTAssertEqual(parser.parse(url), .sharedWishlist(slug: slug, token: token))
  }

  func testParsesCustomShareLink() throws {
    let url = try XCTUnwrap(URL(string: "jiejie://w/\(slug)?token=\(token)"))
    XCTAssertEqual(parser.parse(url), .sharedWishlist(slug: slug, token: token))
  }

  func testParsesPublicLinkWithoutToken() throws {
    let url = try XCTUnwrap(URL(string: "https://gifts.example.com/w/\(slug)"))
    XCTAssertEqual(parser.parse(url), .sharedWishlist(slug: slug, token: nil))
  }

  func testRejectsWrongUniversalLinkHost() throws {
    let url = try XCTUnwrap(URL(string: "https://attacker.example/w/\(slug)?token=\(token)"))
    XCTAssertNil(parser.parse(url))
  }

  func testRejectsShortShareToken() throws {
    let url = try XCTUnwrap(URL(string: "https://gifts.example.com/w/\(slug)?token=short"))
    XCTAssertNil(parser.parse(url))
  }

  func testRejectsMalformedSlug() throws {
    let url = try XCTUnwrap(URL(string: "https://gifts.example.com/w/not%20valid?token=\(token)"))
    XCTAssertNil(parser.parse(url))
  }

  func testParsesAuthenticationCallback() throws {
    let url = try XCTUnwrap(URL(string: "jiejie://auth/callback?code=test-code"))
    XCTAssertEqual(parser.parse(url), .authenticationCallback(url))
  }
}
