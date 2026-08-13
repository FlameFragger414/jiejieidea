import Foundation
import WishlistCore
import XCTest

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

  private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 5,
    _ condition: @MainActor () -> Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return }
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for \(description)")
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

    var announced: [UserProfile] = []
    let model = makeModel(
      profile: profile,
      service: service,
      onProfileChanged: { announced.append($0) }
    )

    model.draft.displayName = "  Mia   Chen "
    model.save(completingOnboarding: true)

    try await waitUntil("the saved state") { model.saveState == .saved }
    XCTAssertEqual(service.recordedSaves.count, 1)
    XCTAssertEqual(service.recordedSaves.first?.draft.normalizedDisplayName, "Mia Chen")
    XCTAssertEqual(service.recordedSaves.first?.completingOnboarding, true)
    XCTAssertEqual(model.profile.displayName, "Mia Chen")
    XCTAssertEqual(announced.count, 1)
    XCTAssertEqual(announced.first?.onboardingCompleted, true)
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

    try await waitUntil("the failed avatar state") {
      if case .failed = model.avatarState { return true }
      return false
    }
    XCTAssertNil(model.profile.avatarPath)
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

    if case .failed = model.avatarState {
      // Expected.
    } else {
      XCTFail("Expected a failed avatar state, got \(model.avatarState)")
    }
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
    var signedOut = false
    let model = makeModel(
      profile: profile,
      service: service,
      onAccountDeleted: { signedOut = true }
    )

    model.beginAccountDeletion()
    model.deletionConfirmationText = "DELETE"
    XCTAssertTrue(model.canConfirmDeletion)
    model.confirmAccountDeletion()

    try await waitUntil("the deleted state") { model.deletion.state == .deleted }
    XCTAssertEqual(service.recordedDeleteCount, 1)
    XCTAssertTrue(signedOut)
  }

  func testAStaleSessionIsAskedToSignInAgain() async throws {
    let profile = TestFixtures.profile()
    let service = FakeProfileService(profile: profile)
    service.setDeleteResult(.failure(AuthenticationFailure.recentSignInRequired))
    var signedOut = false
    let model = makeModel(
      profile: profile,
      service: service,
      onAccountDeleted: { signedOut = true }
    )

    model.beginAccountDeletion()
    model.deletionConfirmationText = "delete"
    model.confirmAccountDeletion()

    try await waitUntil("the failure state") { model.deletion.state.failure != nil }
    XCTAssertEqual(model.deletion.state.failure, .recentSignInRequired)
    XCTAssertFalse(signedOut)
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
