import Foundation
import WishlistCore
import XCTest

/// Collects the callbacks the model raises, so tests can assert on them without capturing a
/// mutable local in an escaping closure.
@MainActor
private final class ChangeRecorder {
  var profiles: [UserProfile] = []
  var accountDeleted = false
}

@MainActor
final class ProfileModelTests: XCTestCase {
  private func makeModel(
    profile: UserProfile,
    service: FakeProfileService,
    onProfileChanged: @escaping @MainActor (UserProfile) -> Void = { _ in },
    onAccountDeleted: @escaping @MainActor () async -> Void = {}
  ) -> ProfileModel {
    ProfileModel(
      profile: profile,
      service: service,
      onProfileChanged: onProfileChanged,
      onAccountDeleted: onAccountDeleted
    )
  }

  // MARK: - Onboarding and editing

  func testOnboardingStartsWithAnEmptyNameWhenOnlyThePlaceholderExists() {
    let profile = TestFixtures.profile(
      displayName: UserProfile.seededDisplayName,
      onboardingCompleted: false
    )
    let model = makeModel(profile: profile, service: FakeProfileService(profile: profile))

    XCTAssertEqual(model.draft.displayName, "")
    XCTAssertFalse(model.canSave)
  }

  func testAnInvalidNameNeverReachesTheService() {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let model = makeModel(profile: profile, service: service)

    model.draft.displayName = "   "
    model.save(completingOnboarding: true)

    XCTAssertTrue(service.recordedSaves.isEmpty)
    XCTAssertEqual(model.displayNameIssue?.field, "displayName")
  }

  func testAnOverlongNameIsRejectedBeforeSaving() {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let model = makeModel(profile: profile, service: service)

    model.draft.displayName = String(repeating: "m", count: 81)
    model.save(completingOnboarding: false)

    XCTAssertTrue(service.recordedSaves.isEmpty)
    XCTAssertNotNil(model.displayNameIssue)
  }

  func testCompletingOnboardingSavesTheNormalizedNameAndAnnouncesTheChange() async throws {
    let profile = TestFixtures.profile(
      displayName: UserProfile.seededDisplayName,
      onboardingCompleted: false
    )
    let service = FakeProfileService(profile: profile)
    service.setSaveResult(.success(TestFixtures.profile(displayName: "Mia Chen")))

    let recorder = ChangeRecorder()
    let model = makeModel(
      profile: profile,
      service: service,
      onProfileChanged: { recorder.profiles.append($0) }
    )

    model.draft.displayName = "  Mia   Chen "
    model.save(completingOnboarding: true)

    try await waitUntil("the saved state") { model.saveState == .saved }
    XCTAssertEqual(service.recordedSaves.count, 1)
    XCTAssertEqual(service.recordedSaves.first?.draft.normalizedDisplayName, "Mia Chen")
    XCTAssertEqual(service.recordedSaves.first?.completingOnboarding, true)
    XCTAssertEqual(model.profile.displayName, "Mia Chen")
    XCTAssertEqual(recorder.profiles.count, 1)
    XCTAssertEqual(recorder.profiles.first?.onboardingCompleted, true)
  }

  func testEditingLaterDoesNotRepeatOnboarding() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let model = makeModel(profile: profile, service: service)

    model.draft.displayName = "Mia C"
    model.save(completingOnboarding: false)

    try await waitUntil("the saved state") { model.saveState == .saved }
    XCTAssertEqual(service.recordedSaves.first?.completingOnboarding, false)
  }

  func testAFailedSaveShowsTheReasonWithoutClaimingSuccess() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    service.setSaveResult(.failure(AuthenticationFailure.serviceUnavailable))
    let model = makeModel(profile: profile, service: service)

    model.draft.displayName = "Mia Chen"
    model.save(completingOnboarding: false)

    try await waitUntil("the failure state") {
      if case .failed = model.saveState { return true }
      return false
    }
    XCTAssertNotEqual(model.saveState, .saved)
  }

  func testAServerSideValidationFailureLandsOnTheField() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    service.setSaveResult(
      .failure(
        ProfileServiceError.validation(
          ValidationIssue(field: "displayName", message: "Enter the name friends will recognise.")
        )
      )
    )
    let model = makeModel(profile: profile, service: service)

    model.draft.displayName = "Mia Chen"
    model.save(completingOnboarding: false)

    try await waitUntil("the field issue") { model.displayNameIssue != nil }
    XCTAssertEqual(model.displayNameIssue?.field, "displayName")
  }

  // MARK: - Avatars

  func testUploadingAnImageStoresAnOwnerScopedObject() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    service.setUploadResult(
      .success(
        TestFixtures.profile(avatarPath: "\(TestFixtures.ownerID.uuidString.lowercased())/x"))
    )
    let model = makeModel(profile: profile, service: service)

    model.selectImage(data: try TestFixtures.pngData())

    try await waitUntil("the uploaded image") { service.recordedUploads.count == 1 }
    let upload = try XCTUnwrap(service.recordedUploads.first)
    XCTAssertEqual(upload.ownerID, TestFixtures.ownerID)
    XCTAssertTrue(ProfileImageObject.isOwned(upload.objectName, by: TestFixtures.ownerID))
    // Preparation always re-encodes to JPEG, which also strips the original metadata.
    XCTAssertEqual(upload.format, .jpeg)
    XCTAssertLessThanOrEqual(upload.data.count, ProfileImageUpload.maximumByteCount)
  }

  func testANonImagePayloadIsRejectedWithoutUploading() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let model = makeModel(profile: profile, service: service)

    model.selectImage(data: Data("<svg></svg>".utf8))

    try await waitUntil("the image issue") { model.imageIssue != nil }
    XCTAssertTrue(service.recordedUploads.isEmpty)
    XCTAssertEqual(model.avatarState, .empty)
  }

  func testAFailedUploadIsReportedAndDoesNotChangeTheProfile() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    service.setUploadResult(.failure(AuthenticationFailure.offline))
    let model = makeModel(profile: profile, service: service)

    model.selectImage(data: try TestFixtures.pngData())

    try await waitUntil("the reported failure") { model.avatarFailureMessage != nil }
    XCTAssertNil(model.profile.avatarPath)
    XCTAssertEqual(model.avatarState, .empty)
  }

  func testAFailedReplacementKeepsTheStoredPhotoOnScreen() async throws {
    let path = "\(TestFixtures.ownerID.uuidString.lowercased())/existing.jpg"
    let profile = TestFixtures.profile(avatarPath: path)
    let service = FakeProfileService(profile: profile)
    let storedImage = try TestFixtures.pngData(width: 4, height: 4)
    service.setAvatarResult(.success(storedImage))
    service.setUploadResult(.failure(AuthenticationFailure.offline))
    let model = makeModel(profile: profile, service: service)

    await model.loadAvatarIfNeeded()
    XCTAssertEqual(model.avatarState, .ready(storedImage))

    model.selectImage(data: try TestFixtures.pngData())

    try await waitUntil("the reported failure") { model.avatarFailureMessage != nil }
    XCTAssertEqual(model.avatarState, .ready(storedImage))
    XCTAssertEqual(model.profile.avatarPath, path)
  }

  func testRemovingAnImageClearsTheProfileReference() async throws {
    let path = "\(TestFixtures.ownerID.uuidString.lowercased())/existing.jpg"
    let profile = TestFixtures.profile(avatarPath: path)
    let service = FakeProfileService(profile: profile)
    service.setRemoveResult(.success(TestFixtures.profile(avatarPath: nil)))
    let model = makeModel(profile: profile, service: service)

    XCTAssertTrue(model.hasAvatar)
    model.removeImage()

    try await waitUntil("the removed image") { service.recordedRemoveCount == 1 }
    XCTAssertNil(model.profile.avatarPath)
    XCTAssertEqual(model.avatarState, .empty)
    XCTAssertFalse(model.hasAvatar)
  }

  func testAnAvatarDownloadFailureIsReportedWithoutBlockingTheScreen() async throws {
    let path = "\(TestFixtures.ownerID.uuidString.lowercased())/existing.jpg"
    let profile = TestFixtures.profile(avatarPath: path)
    let service = FakeProfileService(profile: profile)
    service.setAvatarResult(.failure(AuthenticationFailure.offline))
    let model = makeModel(profile: profile, service: service)

    await model.loadAvatarIfNeeded()

    XCTAssertNotNil(model.avatarFailureMessage)
    XCTAssertEqual(model.avatarState, .empty)
  }

  func testASupersededUploadDoesNotOverwriteTheNewerOne() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let model = makeModel(profile: profile, service: service)
    let data = try TestFixtures.pngData()

    model.selectImage(data: data)
    model.selectImage(data: data)

    try await waitUntil("both uploads to settle") {
      if case .ready = model.avatarState { return true }
      return false
    }
    XCTAssertNil(model.imageIssue)
  }

  // MARK: - Account deletion

  func testDeletionNeedsTheTypedConfirmation() {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let model = makeModel(profile: profile, service: service)

    model.beginAccountDeletion()
    model.deletionConfirmationText = "yes please"

    XCTAssertFalse(model.canConfirmDeletion)
    model.confirmAccountDeletion()
    XCTAssertEqual(service.recordedDeleteCount, 0)
  }

  func testAConfirmedDeletionCallsTheServerAndEndsTheSession() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let recorder = ChangeRecorder()
    let model = makeModel(
      profile: profile,
      service: service,
      onAccountDeleted: { recorder.accountDeleted = true }
    )

    model.beginAccountDeletion()
    model.deletionConfirmationText = "DELETE"
    XCTAssertTrue(model.canConfirmDeletion)
    model.confirmAccountDeletion()

    try await waitUntil("the deleted state") { model.deletion.state == .deleted }
    XCTAssertEqual(service.recordedDeleteCount, 1)
    XCTAssertTrue(recorder.accountDeleted)
  }

  func testAStaleSessionIsAskedToSignInAgain() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    service.setDeleteResult(.failure(AuthenticationFailure.recentSignInRequired))
    let recorder = ChangeRecorder()
    let model = makeModel(
      profile: profile,
      service: service,
      onAccountDeleted: { recorder.accountDeleted = true }
    )

    model.beginAccountDeletion()
    model.deletionConfirmationText = "delete"
    model.confirmAccountDeletion()

    try await waitUntil("the failure state") { model.deletion.state.failure != nil }
    XCTAssertEqual(model.deletion.state.failure, .recentSignInRequired)
    XCTAssertFalse(recorder.accountDeleted)
  }

  func testASecondDeletionRequestWhileRunningIsIgnored() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    let model = makeModel(profile: profile, service: service)

    model.beginAccountDeletion()
    model.deletionConfirmationText = "DELETE"
    model.confirmAccountDeletion()
    model.confirmAccountDeletion()

    try await waitUntil("the deleted state") { model.deletion.state == .deleted }
    XCTAssertEqual(service.recordedDeleteCount, 1)
  }
}
