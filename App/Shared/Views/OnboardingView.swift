import SwiftUI
import WishlistCore

/// Collects the minimum a person needs before the rest of the app makes sense: a name friends will
/// recognise, and optionally a photo.
struct OnboardingView: View {
  @ObservedObject var model: ProfileModel
  let onSignOut: @MainActor @Sendable () async -> Void

  @FocusState private var nameFieldFocused: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        VStack(spacing: 10) {
          Text("Finish setting up")
            .font(.system(.title, design: .rounded, weight: .bold))
          Text("Friends see this name when you share a wishlist with them.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)

        VStack(spacing: 18) {
          ProfileAvatarView(
            displayName: model.draft.normalizedDisplayName,
            state: model.avatarState
          )

          ProfileImagePicker(
            hasExistingImage: model.hasAvatar,
            isBusy: model.avatarState.isBusy,
            onImagePicked: model.selectImage(data:),
            onRemove: model.removeImage
          )

          if let issue = model.imageIssue {
            FailureNotice(message: issue.message)
          }

          VStack(alignment: .leading, spacing: 8) {
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
              .accessibilityHint("Up to 80 characters")

            if let issue = model.displayNameIssue {
              Label(issue.message, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .accessibilityLabel("Error: \(issue.message)")
            }
          }

          Button(action: save) {
            HStack(spacing: 8) {
              if model.saveState.isSaving {
                ProgressView().controlSize(.small)
              }
              Text(model.saveState.isSaving ? "Saving…" : "Continue")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(!model.canSave)

          if case .failed(let message) = model.saveState {
            FailureNotice(message: message)
          }
        }
        .padding(20)
        .giftCard()

        Button("Sign out") {
          Task { @MainActor [onSignOut] in
            await onSignOut()
          }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
      }
      .padding(24)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .background(GiftPalette.canvas)
    .navigationTitle("Welcome")
    .task {
      await model.loadAvatarIfNeeded()
    }
  }

  private func save() {
    nameFieldFocused = false
    model.save(completingOnboarding: true)
  }
}
