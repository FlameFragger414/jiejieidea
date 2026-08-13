import SwiftUI
import WishlistCore

/// Profile editing, sign-out, and permanent account deletion.
struct ProfileView: View {
  @ObservedObject var model: ProfileModel
  let email: String?
  let onSignOut: @MainActor @Sendable () async -> Void

  @FocusState private var nameFieldFocused: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        photoCard
        detailsCard
        accountCard
        dangerCard
      }
      .padding(20)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .background(GiftPalette.canvas)
    .navigationTitle("Profile")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task {
      await model.loadAvatarIfNeeded()
    }
    .task(id: model.saveState) {
      // Let the "Saved" confirmation fade rather than sit on screen forever.
      guard model.saveState == .saved else { return }
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      guard !Task.isCancelled else { return }
      model.acknowledgeSaveResult()
    }
    .sheet(isPresented: deletionSheetBinding) {
      AccountDeletionSheet(model: model)
    }
  }

  private var photoCard: some View {
    VStack(spacing: 16) {
      ProfileAvatarView(displayName: model.profile.displayName, state: model.avatarState)
      ProfileImagePicker(
        hasExistingImage: model.hasAvatar,
        isBusy: model.avatarState.isBusy,
        onImagePicked: model.selectImage(data:),
        onRemove: model.removeImage
      )
      if let issue = model.imageIssue {
        FailureNotice(message: issue.message)
      }
      if case .failed(let message) = model.avatarState {
        FailureNotice(message: message)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity)
    .giftCard()
  }

  private var detailsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Your name")
        .font(.headline)
      TextField("Mia Chen", text: $model.draft.displayName)
        .textFieldStyle(.roundedBorder)
        .focused($nameFieldFocused)
        .submitLabel(.done)
        .onSubmit(save)
        #if os(iOS)
          .textContentType(.name)
        #endif
        .accessibilityLabel("Your name")

      if let issue = model.displayNameIssue {
        Label(issue.message, systemImage: "exclamationmark.circle.fill")
          .font(.footnote)
          .foregroundStyle(.red)
          .accessibilityLabel("Error: \(issue.message)")
      }

      HStack(spacing: 12) {
        Button(action: save) {
          HStack(spacing: 8) {
            if model.saveState.isSaving {
              ProgressView().controlSize(.small)
            }
            Text(model.saveState.isSaving ? "Saving…" : "Save changes")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canSave)

        if model.saveState == .saved {
          Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(GiftPalette.sage)
            .transition(.opacity)
            .accessibilityLabel("Your profile was saved")
        }
      }

      if case .failed(let message) = model.saveState {
        FailureNotice(message: message)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .giftCard()
  }

  private var accountCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Account")
        .font(.headline)
      if let email {
        LabeledContent("Signed in as", value: email)
          .accessibilityLabel("Signed in as \(email)")
      }
      Button("Sign out") {
        Task { @MainActor [onSignOut] in
          await onSignOut()
        }
      }
      .buttonStyle(.bordered)
      .accessibilityHint("Ends this session on this device")
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .giftCard()
  }

  private var dangerCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Delete account", systemImage: "exclamationmark.octagon.fill")
        .font(.headline)
        .foregroundStyle(.red)
      Text(
        "Deleting your account permanently removes your profile, photo, wishlists, and reservation history. This cannot be undone."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      Button("Delete my account…", role: .destructive) {
        model.beginAccountDeletion()
      }
      .buttonStyle(.bordered)
      .disabled(model.deletion.state.isDeleting)

      if let failure = model.deletion.state.failure {
        FailureNotice(message: failure.userMessage)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .giftCard()
  }

  private var deletionSheetBinding: Binding<Bool> {
    Binding(
      get: { model.deletion.state == .confirming || model.deletion.state.isDeleting },
      set: { isPresented in
        if !isPresented {
          model.cancelAccountDeletion()
        }
      }
    )
  }

  private func save() {
    nameFieldFocused = false
    model.save(completingOnboarding: false)
  }
}

/// The explicit destructive-action warning and typed confirmation.
struct AccountDeletionSheet: View {
  @ObservedObject var model: ProfileModel
  @FocusState private var confirmationFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("This deletes everything", systemImage: "exclamationmark.octagon.fill")
        .font(.system(.title3, design: .rounded, weight: .bold))
        .foregroundStyle(.red)

      VStack(alignment: .leading, spacing: 8) {
        Text("Deleting your account removes:")
        Text("• your profile and photo")
        Text("• every wishlist and item you own")
        Text("• every gift you reserved for other people")
        Text("• your notifications and devices")
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      .accessibilityElement(children: .combine)

      Text(
        "Nothing can be recovered afterwards. If you signed in a long time ago you may be asked to sign in again first."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 8) {
        Text("Type \(AccountDeletionConfirmation.requiredPhrase) to confirm")
          .font(.subheadline.weight(.semibold))
        TextField(AccountDeletionConfirmation.requiredPhrase, text: $model.deletionConfirmationText)
          .textFieldStyle(.roundedBorder)
          .focused($confirmationFocused)
          #if os(iOS)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
          #endif
          .accessibilityLabel("Deletion confirmation")
          .accessibilityHint(
            "Type \(AccountDeletionConfirmation.requiredPhrase) to enable the delete button")
      }

      if let failure = model.deletion.state.failure {
        FailureNotice(message: failure.userMessage)
      }

      HStack {
        Button("Keep my account") {
          model.cancelAccountDeletion()
        }
        .buttonStyle(.bordered)
        .disabled(model.deletion.state.isDeleting)

        Spacer()

        Button(role: .destructive) {
          model.confirmAccountDeletion()
        } label: {
          HStack(spacing: 8) {
            if model.deletion.state.isDeleting {
              ProgressView().controlSize(.small)
            }
            Text(model.deletion.state.isDeleting ? "Deleting…" : "Delete permanently")
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!model.canConfirmDeletion)
      }
    }
    .padding(24)
    .frame(minWidth: 340, maxWidth: 520, minHeight: 420)
    .onAppear { confirmationFocused = true }
  }
}
