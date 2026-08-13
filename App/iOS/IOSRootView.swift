import SwiftUI

struct IOSRootView: View {
  var body: some View {
    TabView {
      NavigationStack {
        WishlistDashboardView()
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
    }
    .tint(GiftPalette.plum)
  }
}
