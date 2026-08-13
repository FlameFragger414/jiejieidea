import Combine
import Foundation
import WishlistCore

/// Drives onboarding, profile editing, avatar management, and account deletion.
@MainActor
final class ProfileModel: ObservableObject {
  enum SaveState: Equatable {
    case idle
    case saving
    case saved
    case failed(String)

    var isSaving: Bool { self == .saving }
  }

  enum AvatarState: Equatable {
    case empty
    case loading
    case ready(Data)
    case uploading

    var isBusy: Bool { self == .loading || self == .uploading }

    var imageData: Data? {
      if case .ready(let data) = self { return data }
      return nil
    }
  }

  @Published var draft: ProfileDraft
  @Published var deletionConfirmationText = ""
  @Published private(set) var profile: UserProfile
  @Published private(set) var saveState: SaveState = .idle
  @Published private(set) var avatarState: AvatarState = .empty
  /// Reported separately from `avatarState` so a failed replacement still shows the stored photo.
  @Published private(set) var avatarFailureMessage: String? = nil
  @Published private(set) var fieldIssue: ValidationIssue? = nil
  @Published private(set) var deletion = AccountDeletionRequest()

  private let service: any ProfileService
  private let onProfileChanged: @MainActor (UserProfile) -> Void
  private let onAccountDeleted: @MainActor () async -> Void

  /// The last image successfully shown, kept so an interrupted replacement can put it back rather
  /// than leaving the person looking at an empty circle while their photo is still stored.
  private var lastShownImageData: Data?
  private var avatarLoads = AsyncOperationSequence()
  private var saveTask: Task<Void, Never>?
  private var avatarTask: Task<Void, Never>?
  private var deletionTask: Task<Void, Never>?

  init(
    profile: UserProfile,
    service: any ProfileService,
    onProfileChanged: @escaping @MainActor (UserProfile) -> Void = { _ in },
    onAccountDeleted: @escaping @MainActor () async -> Void = {}
  ) {
    self.profile = profile
    self.service = service
    self.onProfileChanged = onProfileChanged
    self.onAccountDeleted = onAccountDeleted
    draft = ProfileDraft(profile: profile)
  }

  var canSave: Bool {
    draft.isValid && !saveState.isSaving && !avatarState.isBusy
  }

  var hasAvatar: Bool {
    profile.avatarPath != nil
  }

  var canConfirmDeletion: Bool {
    AccountDeletionConfirmation.matches(deletionConfirmationText) && !deletion.state.isDeleting
  }

  /// Field-level feedback shown only once the person has typed something.
  var displayNameIssue: ValidationIssue? {
    if let fieldIssue, fieldIssue.field == "displayName" { return fieldIssue }
    guard !draft.displayName.isEmpty else { return nil }
    return draft.validationIssues().first { $0.field == "displayName" }
  }

  var imageIssue: ValidationIssue? {
    fieldIssue.flatMap { $0.field == "profileImage" ? $0 : nil }
  }

  // MARK: - Avatar

  func loadAvatarIfNeeded() async {
    guard let path = profile.avatarPath else {
      avatarState = .empty
      return
    }
    guard avatarState.imageData == nil, !avatarState.isBusy else { return }
    await loadAvatar(path: path)
  }

  private func loadAvatar(path: String) async {
    let token = avatarLoads.start()
    avatarFailureMessage = nil
    avatarState = .loading
    do {
      let data = try await service.avatarData(path: path)
      guard avatarLoads.isCurrent(token) else { return }
      lastShownImageData = data
      avatarState = .ready(data)
    } catch {
      guard avatarLoads.isCurrent(token) else { return }
      avatarFailureMessage = ProfileFailureMapping.error(for: error).userMessage
      avatarState = .empty
    }
  }

  /// Accepts freshly picked image data, prepares it, uploads it, and records the new path.
  func selectImage(data: Data) {
    fieldIssue = nil
    avatarFailureMessage = nil
    avatarTask?.cancel()
    let token = avatarLoads.start()
    avatarState = .uploading

    avatarTask = Task { [weak self, service, profile] in
      do {
        // Decoding and resizing happen off the main actor so a large photo cannot stall the UI.
        let prepared = try await Task.detached(priority: .userInitiated) {
          try ProfileImagePreparation.prepared(data)
        }.value
        try Task.checkCancellation()
        let upload = try ProfileImageUpload(ownerID: profile.id, data: prepared)
        let updated = try await service.uploadAvatar(upload)
        try Task.checkCancellation()

        guard let self, self.avatarLoads.isCurrent(token) else { return }
        self.apply(updated, resettingDraft: false)
        self.lastShownImageData = prepared
        self.avatarState = .ready(prepared)
      } catch is CancellationError {
        guard let self, self.avatarLoads.isCurrent(token) else { return }
        self.restoreAvatarStateAfterInterruption()
      } catch let issue as ValidationIssue {
        guard let self, self.avatarLoads.isCurrent(token) else { return }
        self.fieldIssue = issue
        self.restoreAvatarStateAfterInterruption()
      } catch {
        guard let self, self.avatarLoads.isCurrent(token) else { return }
        let mapped = ProfileFailureMapping.error(for: error)
        self.fieldIssue = mapped.validationIssue
        self.avatarFailureMessage = mapped.userMessage
        // The stored photo is unchanged, so it stays on screen beside the failure.
        self.restoreAvatarStateAfterInterruption()
      }
    }
  }

  func removeImage() {
    guard hasAvatar, !avatarState.isBusy else { return }
    fieldIssue = nil
    avatarFailureMessage = nil
    avatarTask?.cancel()
    let token = avatarLoads.start()
    avatarState = .uploading

    avatarTask = Task { [weak self, service] in
      do {
        let updated = try await service.removeAvatar()
        guard let self, self.avatarLoads.isCurrent(token) else { return }
        self.apply(updated, resettingDraft: false)
        self.lastShownImageData = nil
        self.avatarState = .empty
      } catch {
        guard let self, self.avatarLoads.isCurrent(token) else { return }
        self.avatarFailureMessage = ProfileFailureMapping.error(for: error).userMessage
        self.restoreAvatarStateAfterInterruption()
      }
    }
  }

  private func restoreAvatarStateAfterInterruption() {
    if let data = lastShownImageData {
      avatarState = .ready(data)
    } else {
      avatarState = .empty
    }
  }

  // MARK: - Saving

  func save(completingOnboarding: Bool) {
    guard canSave else {
      fieldIssue = draft.validationIssues().first
      return
    }

    fieldIssue = nil
    saveState = .saving
    saveTask?.cancel()
    saveTask = Task { [weak self, service, draft] in
      do {
        let updated = try await service.saveProfile(
          draft,
          completingOnboarding: completingOnboarding
        )
        try Task.checkCancellation()
        guard let self else { return }
        self.apply(updated, resettingDraft: true)
        self.saveState = .saved
      } catch is CancellationError {
        self?.saveState = .idle
      } catch {
        guard let self else { return }
        let mapped = ProfileFailureMapping.error(for: error)
        self.fieldIssue = mapped.validationIssue
        self.saveState = .failed(mapped.userMessage)
      }
    }
  }

  func acknowledgeSaveResult() {
    guard !saveState.isSaving else { return }
    saveState = .idle
  }

  /// An avatar change must not discard a name the person is still typing, so only a completed save
  /// refreshes the draft.
  private func apply(_ updated: UserProfile, resettingDraft: Bool) {
    profile = updated
    if resettingDraft {
      draft = ProfileDraft(profile: updated)
    }
    onProfileChanged(updated)
  }

  // MARK: - Account deletion

  func beginAccountDeletion() {
    deletionConfirmationText = ""
    deletion.beginConfirmation()
  }

  func cancelAccountDeletion() {
    deletion.cancel()
    deletionConfirmationText = ""
  }

  func confirmAccountDeletion() {
    switch deletion.submit(confirmationText: deletionConfirmationText) {
    case .alreadyInFlight, .confirmationMismatch:
      return
    case .delete:
      deletionTask?.cancel()
      deletionTask = Task { [weak self, service] in
        do {
          try await service.deleteAccount()
          guard let self else { return }
          self.deletion.markDeleted()
          await self.onAccountDeleted()
        } catch {
          guard let self else { return }
          let failure =
            ProfileFailureMapping.error(for: error).authenticationFailure ?? .unknown
          self.deletion.markFailed(failure)
        }
      }
    }
  }
}
