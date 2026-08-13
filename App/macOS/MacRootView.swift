import SwiftUI
import WishlistCore

struct MacRootView: View {
  private enum Section: String, CaseIterable, Identifiable {
    case wishlists
    case myGifts
    case profile

    var id: String { rawValue }

    var title: String {
      switch self {
      case .wishlists: "Wishlists"
      case .myGifts: "My gifts"
      case .profile: "Profile"
      }
    }

    var symbol: String {
      switch self {
      case .wishlists: "gift.fill"
      case .myGifts: "checkmark.seal.fill"
      case .profile: "person.crop.circle"
      }
    }
  }

  @EnvironmentObject private var session: SessionController
  @EnvironmentObject private var model: AppModel
  @State private var selection: Section? = .wishlists

  var body: some View {
    AuthenticationGate { profile in
      if let service = session.profileService {
        SignedInContentView(profile: profile, service: service, session: session) {
          splitView
        }
      }
    }
    .tint(GiftPalette.plum)
  }

  private var splitView: some View {
    NavigationSplitView {
      List(Section.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.symbol)
          .tag(section)
      }
      .navigationTitle("Jiejie")
      .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      NavigationStack {
        switch selection ?? .wishlists {
        case .wishlists:
          WishlistDashboardView()
            .environmentObject(model)
        case .myGifts:
          MyGiftsView()
        case .profile:
          MacProfileDetail()
        }
      }
    }
  }
}

/// Bridges the profile model created by `SignedInContentView` into the detail column.
struct MacProfileDetail: View {
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
