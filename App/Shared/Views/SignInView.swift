import AuthenticationServices
import SwiftUI
import WishlistCore

struct SignInView: View {
  @EnvironmentObject private var session: SessionController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var emailFieldFocused: Bool
  @State private var appleNonceStore = AppleSignInNonceStore()

  var body: some View {
    ScrollView {
      VStack(spacing: 26) {
        header

        VStack(spacing: 16) {
          switch session.magicLink.state {
          case .sent(let address):
            linkSentPanel(address: address)
          case .idle, .sending, .failed:
            emailPanel
          }
        }
        .giftCard()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: session.magicLink.state)

        if session.appleSignInEnabled {
          appleSection
        }

        Text(
          "Jiejie never shows wishlist owners who reserved a gift. Signing in only links your wishlists and reservations to you."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      }
      .padding(24)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
    }
    .background(GiftPalette.canvas)
    .navigationTitle("Sign in")
  }

  private var header: some View {
    VStack(spacing: 10) {
      Image(systemName: "gift.fill")
        .font(.system(size: 40, weight: .semibold))
        .foregroundStyle(GiftPalette.plum)
        .frame(width: 84, height: 84)
        .background(GiftPalette.blush.opacity(0.3), in: Circle())
        .accessibilityHidden(true)
      Text("Welcome to Jiejie")
        .font(.system(.title, design: .rounded, weight: .bold))
      Text("Keep your wishlists in one place and let friends surprise you.")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 12)
    .accessibilityElement(children: .combine)
  }

  private var emailPanel: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Sign in with an email link")
        .font(.headline)

      TextField("you@example.com", text: $session.emailField)
        .textFieldStyle(.roundedBorder)
        .focused($emailFieldFocused)
        .disableAutocorrection(true)
        .submitLabel(.go)
        .onSubmit(sendLink)
        #if os(iOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
        #endif
        .accessibilityLabel("Email address")
        .accessibilityHint("Jiejie sends a one-time sign-in link to this address")

      if let issue = session.magicLinkFieldIssue {
        Label(issue.message, systemImage: "exclamationmark.circle.fill")
          .font(.footnote)
          .foregroundStyle(.red)
          .accessibilityLabel("Error: \(issue.message)")
      }

      Button(action: sendLink) {
        HStack(spacing: 8) {
          if session.magicLink.state.isSending {
            ProgressView()
              .controlSize(.small)
          }
          Text(session.magicLink.state.isSending ? "Sending link…" : "Email me a sign-in link")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!canSendLink)
      .accessibilityHint("Sends a one-time sign-in link to the address above")

      if let failure = session.magicLink.state.failure {
        FailureNotice(message: failure.userMessage)
      }
    }
    .padding(18)
  }

  private func linkSentPanel(address: EmailAddress) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Check your inbox", systemImage: "envelope.badge.fill")
        .font(.headline)
        .foregroundStyle(GiftPalette.plum)
      Text(
        "We sent a sign-in link to \(address.normalized). Open it on this device to finish signing in."
      )
      .foregroundStyle(.secondary)
      Text("The link expires after a short time and can only be used once.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Button("Use a different address") {
        session.resetMagicLink()
        emailFieldFocused = true
      }
      .buttonStyle(.bordered)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var appleSection: some View {
    VStack(spacing: 12) {
      Text("or")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      SignInWithAppleButton(.signIn) { request in
        guard let hashedNonce = appleNonceStore.prepare() else {
          // Without a nonce there is no replay protection, so the request must not run. Apple still
          // presents its sheet, so the failure is reported rather than left as silence.
          Task { @MainActor [session] in
            await session.completeAppleSignIn(.failure(.appleCredentialRejected))
          }
          return
        }
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
      } onCompletion: { result in
        let outcome = appleNonceStore.outcome(for: result)
        Task { @MainActor [session] in
          await session.completeAppleSignIn(outcome)
        }
      }
      .signInWithAppleButtonStyle(.black)
      .frame(height: 48)
      .frame(maxWidth: 420)
      .disabled(session.phase.isBusy)
      .accessibilityLabel("Sign in with Apple")
      .accessibilityHint("Uses your Apple Account to sign in without an email link")

      if let failure = session.appleSignInFailure {
        FailureNotice(message: failure.userMessage)
      }
    }
  }

  private var canSendLink: Bool {
    session.magicLink.canSubmit
      && !session.emailField.isEmpty
      && session.magicLinkFieldIssue == nil
      && !session.phase.isBusy
  }

  private func sendLink() {
    guard canSendLink else { return }
    emailFieldFocused = false
    session.requestMagicLink()
  }
}

struct FailureNotice: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.footnote)
      .foregroundStyle(.red)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel("Error: \(message)")
  }
}
