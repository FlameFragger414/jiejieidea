import Foundation
import XCTest

@testable import WishlistCore

final class ProfileTests: XCTestCase {
  private let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  private let otherID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

  private func profile(
    displayName: String,
    avatarPath: String? = nil,
    onboardingCompleted: Bool = false
  ) -> UserProfile {
    UserProfile(
      id: ownerID,
      displayName: displayName,
      avatarPath: avatarPath,
      onboardingCompleted: onboardingCompleted,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }

  func testSeededNameIsNotTreatedAsAChosenName() {
    let seeded = profile(displayName: UserProfile.seededDisplayName)
    XCTAssertFalse(seeded.hasChosenDisplayName)
    XCTAssertEqual(seeded.editableDisplayName, "")
    XCTAssertTrue(seeded.requiresOnboarding)
  }

  func testProviderSuppliedNameIsPreFilled() {
    let fromApple = profile(displayName: "Mia Chen", onboardingCompleted: true)
    XCTAssertTrue(fromApple.hasChosenDisplayName)
    XCTAssertEqual(fromApple.editableDisplayName, "Mia Chen")
    XCTAssertFalse(fromApple.requiresOnboarding)
  }

  func testDecodesSnakeCaseColumnsFromPostgREST() throws {
    let json = """
      {
        "id": "10000000-0000-0000-0000-000000000001",
        "display_name": "Mia Chen",
        "avatar_path": "10000000-0000-0000-0000-000000000001/abc.jpg",
        "onboarding_completed": true,
        "created_at": 0,
        "updated_at": 0
      }
      """
    let decoded = try JSONDecoder().decode(UserProfile.self, from: Data(json.utf8))
    XCTAssertEqual(decoded.id, ownerID)
    XCTAssertEqual(decoded.displayName, "Mia Chen")
    XCTAssertEqual(decoded.avatarPath, "10000000-0000-0000-0000-000000000001/abc.jpg")
    XCTAssertTrue(decoded.onboardingCompleted)
  }

  func testMutationResultExposesReplacedAvatarForCleanup() throws {
    let json = """
      {
        "id": "10000000-0000-0000-0000-000000000001",
        "display_name": "Mia Chen",
        "avatar_path": "10000000-0000-0000-0000-000000000001/new.jpg",
        "onboarding_completed": true,
        "created_at": 0,
        "updated_at": 0,
        "replaced_avatar_path": "10000000-0000-0000-0000-000000000001/old.jpg"
      }
      """
    let result = try JSONDecoder().decode(ProfileMutationResult.self, from: Data(json.utf8))
    XCTAssertEqual(result.replacedAvatarPath, "10000000-0000-0000-0000-000000000001/old.jpg")
    XCTAssertEqual(result.profile.avatarPath, "10000000-0000-0000-0000-000000000001/new.jpg")
    XCTAssertTrue(result.profile.onboardingCompleted)
  }

  func testDraftRejectsEmptyOrWhitespaceOnlyName() {
    XCTAssertEqual(ProfileDraft(displayName: "").validationIssues().first?.field, "displayName")
    XCTAssertEqual(
      ProfileDraft(displayName: "   \n").validationIssues().first?.field, "displayName")
  }

  func testDraftRejectsOverlongName() {
    let draft = ProfileDraft(displayName: String(repeating: "m", count: 81))
    XCTAssertFalse(draft.isValid)
    XCTAssertEqual(draft.validationIssues().first?.field, "displayName")
  }

  func testDraftAcceptsBoundaryLengthName() {
    XCTAssertTrue(ProfileDraft(displayName: String(repeating: "m", count: 80)).isValid)
  }

  func testDraftNormalizesWhitespaceRuns() {
    let draft = ProfileDraft(displayName: "  Mia\t\tChen \n")
    XCTAssertEqual(draft.normalizedDisplayName, "Mia Chen")
    XCTAssertTrue(draft.isValid)
  }

  func testDraftRejectsControlCharacters() {
    let draft = ProfileDraft(displayName: "Mia\u{0007}Chen")
    XCTAssertFalse(draft.isValid)
  }

  func testDraftFromProfileSkipsSeededName() {
    XCTAssertEqual(
      ProfileDraft(profile: profile(displayName: UserProfile.seededDisplayName)).displayName,
      ""
    )
    XCTAssertEqual(ProfileDraft(profile: profile(displayName: "Mia Chen")).displayName, "Mia Chen")
  }

  func testProfileImageObjectNameIsScopedToTheOwner() {
    let identifier = UUID(uuidString: "40000000-0000-0000-0000-000000000009")!
    let name = ProfileImageObject.name(ownerID: ownerID, format: .jpeg, identifier: identifier)
    XCTAssertEqual(
      name,
      "10000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000009.jpg"
    )
    XCTAssertTrue(ProfileImageObject.isOwned(name, by: ownerID))
    XCTAssertFalse(ProfileImageObject.isOwned(name, by: otherID))
    XCTAssertEqual(ProfileImageObject.owner(of: name), ownerID)
  }

  func testProfileImageObjectRejectsForgedOrMalformedNames() {
    let cases = [
      "10000000-0000-0000-0000-000000000002/40000000-0000-0000-0000-000000000009.jpg",
      "40000000-0000-0000-0000-000000000009.jpg",
      "10000000-0000-0000-0000-000000000001/nested/40000000-0000-0000-0000-000000000009.jpg",
      "10000000-0000-0000-0000-000000000001/../40000000-0000-0000-0000-000000000009.jpg",
      "10000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000009.svg",
      "10000000-0000-0000-0000-000000000001/avatar.jpg",
      "10000000-0000-0000-0000-000000000001/",
    ]
    for objectName in cases {
      XCTAssertFalse(
        ProfileImageObject.isOwned(objectName, by: ownerID),
        "\(objectName) should not be treated as owned"
      )
    }
  }

  func testDetectsSupportedImageFormatsFromLeadingBytes() {
    XCTAssertEqual(ProfileImageFormat.detected(in: Self.jpegData()), .jpeg)
    XCTAssertEqual(ProfileImageFormat.detected(in: Self.pngData()), .png)
    XCTAssertEqual(ProfileImageFormat.detected(in: Self.heicData()), .heic)
    XCTAssertEqual(ProfileImageFormat.detected(in: Self.webpData()), .webp)
  }

  func testRejectsUnsupportedOrDisguisedPayloads() {
    let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)
    XCTAssertNil(ProfileImageFormat.detected(in: svg))
    XCTAssertNil(ProfileImageFormat.detected(in: Data(repeating: 0, count: 32)))
    XCTAssertNil(ProfileImageFormat.detected(in: Data("GIF89a".utf8)))
  }

  func testUploadDerivesOwnerScopedObjectNameAndContentType() throws {
    let upload = try ProfileImageUpload(
      ownerID: ownerID,
      data: Self.pngData(),
      identifier: UUID(uuidString: "40000000-0000-0000-0000-000000000009")!
    )
    XCTAssertEqual(upload.format, .png)
    XCTAssertEqual(upload.contentType, "image/png")
    XCTAssertEqual(
      upload.objectName,
      "10000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000009.png"
    )
    XCTAssertTrue(ProfileImageObject.isOwned(upload.objectName, by: ownerID))
  }

  func testUploadRejectsEmptyOversizedAndUnsupportedData() {
    XCTAssertThrowsError(try ProfileImageUpload(ownerID: ownerID, data: Data()))
    XCTAssertThrowsError(
      try ProfileImageUpload(ownerID: ownerID, data: Data("not an image".utf8))
    )

    var oversized = Self.pngData()
    oversized.append(Data(repeating: 0, count: ProfileImageUpload.maximumByteCount))
    XCTAssertThrowsError(try ProfileImageUpload(ownerID: ownerID, data: oversized)) { error in
      XCTAssertEqual((error as? ValidationIssue)?.field, "profileImage")
    }
  }

  private static func jpegData() -> Data {
    var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]
    bytes.append(contentsOf: [UInt8](repeating: 0x11, count: 12))
    return Data(bytes)
  }

  private static func pngData() -> Data {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    bytes.append(contentsOf: [UInt8](repeating: 0x22, count: 12))
    return Data(bytes)
  }

  private static func heicData() -> Data {
    var bytes: [UInt8] = [0x00, 0x00, 0x00, 0x18]
    bytes.append(contentsOf: Array("ftyp".utf8))
    bytes.append(contentsOf: Array("heic".utf8))
    bytes.append(contentsOf: [UInt8](repeating: 0x33, count: 8))
    return Data(bytes)
  }

  private static func webpData() -> Data {
    var bytes = Array("RIFF".utf8)
    bytes.append(contentsOf: [0x20, 0x00, 0x00, 0x00])
    bytes.append(contentsOf: Array("WEBP".utf8))
    bytes.append(contentsOf: [UInt8](repeating: 0x44, count: 8))
    return Data(bytes)
  }
}
