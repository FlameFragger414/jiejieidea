import SwiftUI
import WishlistCore

struct IOSRootView: View {
  @EnvironmentObject private var session: SessionController
  @EnvironmentObject private var model: AppModel

  var body: some View {
    AuthenticationGate { profile in
      if let service = session.profileService {
        SignedInContentView(profile: profile, service: service, session: session) {
          signedInTabs
        }
      }
    }
    .tint(GiftPalette.plum)
  }

  private var signedInTabs: some View {
    TabView {
      NavigationStack {
        WishlistDashboardView()
          .environmentObject(model)
      }
      .tabItem {
        Label("Wishlists", systemImage: "gift.fill")
      }

      NavigationStack {
        MyGiftsView()
      }
      .tabItem {
        Label("My gifts", systemImage: "checkmark.seal.fill")
      }

      NavigationStack {
        ProfileTab()
      }
      .tabItem {
        Label("Profile", systemImage: "person.crop.circle")
      }
    }
  }
}

/// Bridges the profile model created by `SignedInContentView` into a tab.
struct ProfileTab: View {
  @EnvironmentObject private var session: SessionController
  @EnvironmentObject private var profileModel: ProfileModel

  var body: some View {
    ProfileView(
      model: profileModel,
      email: session.phase.user?.email
    ) {
      await session.signOut()
    }
  }
}
