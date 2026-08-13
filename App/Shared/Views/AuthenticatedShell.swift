import SwiftUI
import WishlistCore

/// Chooses the screen for the current authentication phase.
///
/// Both platform roots wrap this so the signed-out, onboarding, offline, and authenticated states
/// behave identically on iOS and macOS.
struct AuthenticationGate<Content: View>: View {
  @EnvironmentObject private var session: SessionController
  @ViewBuilder let authenticatedContent: (UserProfile) -> Content

  var body: some View {
    Group {
      if let problem = session.configurationProblem {
        SetupRequiredView(message: problem.userMessage)
      } else {
        switch session.phase {
        case .restoringSession, .authenticating:
          RestoringSessionView(isSigningIn: session.phase == .authenticating)
        case .signedOut:
          SignInView()
        case .unverified(_, let problem):
          UnverifiedSessionView(problem: problem)
        case .onboardingRequired, .authenticated:
          if let profile = session.profile {
            authenticatedContent(profile)
          } else {
            RestoringSessionView(isSigningIn: false)
          }
        }
      }
    }
    .task { session.start() }
    .onOpenURL { url in
      Task { await session.handle(url: url) }
    }
  }
}

/// Presents onboarding until the profile is complete, then the app content.
struct SignedInContentView<Content: View>: View {
  @EnvironmentObject private var session: SessionController
  @StateObject private var model: ProfileModel
  @ViewBuilder let content: () -> Content

  init(
    profile: UserProfile,
    service: any ProfileService,
    session: SessionController,
    @ViewBuilder content: @escaping () -> Content
  ) {
    _model = StateObject(
      wrappedValue: ProfileModel(
        profile: profile,
        service: service,
        onProfileChanged: { [weak session] updated in session?.profileDidChange(updated) },
        onAccountDeleted: { [weak session] in await session?.accountWasDeleted() }
      )
    )
    self.content = content
  }

  var body: some View {
    Group {
      if model.profile.requiresOnboarding {
        OnboardingView(model: model) {
          await session.signOut()
        }
      } else {
        content()
      }
    }
    .environmentObject(model)
  }
}

struct RestoringSessionView: View {
  let isSigningIn: Bool

  var body: some View {
    VStack(spacing: 14) {
      ProgressView()
      Text(isSigningIn ? "Signing you in…" : "Checking your sign-in…")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GiftPalette.canvas)
    .accessibilityElement(children: .combine)
  }
}

/// Shown when a session may exist but cannot be verified, usually because the device is offline.
struct UnverifiedSessionView: View {
  @EnvironmentObject private var session: SessionController
  let problem: SessionVerificationProblem
  @State private var isRetrying = false

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "wifi.exclamationmark")
        .font(.system(size: 36, weight: .semibold))
        .foregroundStyle(GiftPalette.plum)
        .accessibilityHidden(true)
      Text("Can’t confirm your sign-in")
        .font(.system(.title2, design: .rounded, weight: .bold))
      Text(problem.userMessage)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)

      Button {
        Task {
          isRetrying = true
          await session.retryVerification()
          isRetrying = false
        }
      } label: {
        HStack(spacing: 8) {
          if isRetrying {
            ProgressView().controlSize(.small)
          }
          Text(isRetrying ? "Checking…" : "Try again")
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(isRetrying)

      Button("Sign out") {
        Task { await session.signOut() }
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(GiftPalette.canvas)
  }
}
