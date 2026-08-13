import SwiftUI

struct MyGiftsView: View {
  var body: some View {
    EmptyStateView(
      title: "No reserved gifts",
      systemImage: "giftcard",
      description:
        "Gifts you reserve for other people will appear here. Wishlist owners never see this activity."
    )
    .navigationTitle("My gifts")
  }
}
