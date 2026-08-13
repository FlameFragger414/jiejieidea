import SwiftUI

struct MacRootView: View {
  private enum Section: String, CaseIterable, Identifiable {
    case wishlists
    case myGifts

    var id: String { rawValue }

    var title: String {
      switch self {
      case .wishlists: "Wishlists"
      case .myGifts: "My gifts"
      }
    }

    var symbol: String {
      switch self {
      case .wishlists: "gift.fill"
      case .myGifts: "checkmark.seal.fill"
      }
    }
  }

  @State private var selection: Section? = .wishlists

  var body: some View {
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
        case .myGifts:
          MyGiftsView()
        }
      }
    }
    .tint(GiftPalette.plum)
  }
}
