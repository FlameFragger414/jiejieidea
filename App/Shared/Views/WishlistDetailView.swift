import SwiftUI
import WishlistCore

struct WishlistDetailView: View {
  @EnvironmentObject private var model: AppModel
  let wishlistID: UUID

  var body: some View {
    Group {
      if let wishlist = model.wishlist(id: wishlistID) {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            header(wishlist)

            if model.items(in: wishlistID).isEmpty {
              EmptyStateView(
                title: "No gifts yet",
                systemImage: "gift",
                description: "Items you add will appear here in your chosen order."
              )
              .frame(minHeight: 260)
            } else {
              LazyVStack(spacing: 14) {
                ForEach(model.items(in: wishlistID)) { item in
                  OwnerItemCard(item: item) { status in
                    model.setItemStatus(itemID: item.id, in: wishlistID, status: status)
                  }
                }
              }
            }
          }
          .padding(20)
        }
        .background(GiftPalette.canvas)
        .navigationTitle(wishlist.name)
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
        #endif
      } else {
        EmptyStateView(
          title: "Wishlist not found",
          systemImage: "questionmark.folder",
          description: "This wishlist may have been archived or removed."
        )
      }
    }
  }

  private func header(_ wishlist: Wishlist) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text(wishlist.type.displayName.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(GiftPalette.berry)
          Text(wishlist.name)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
          if !wishlist.description.isEmpty {
            Text(wishlist.description)
              .font(.body)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 16)
        PrivacySeal()
      }

      Divider()
      Text(
        "Reservations stay hidden from you, including which gift was reserved and who reserved it."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
      .accessibilityLabel("Privacy: Reservations stay hidden from the wishlist owner.")
    }
    .padding(20)
    .giftCard()
  }
}

private struct OwnerItemCard: View {
  let item: WishlistItem
  let setStatus: (WishlistItemStatus) -> Void

  var body: some View {
    HStack(spacing: 16) {
      ZStack {
        LinearGradient(
          colors: [GiftPalette.blush.opacity(0.7), GiftPalette.plum.opacity(0.22)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Image(systemName: item.category == "Tech" ? "camera.fill" : "shippingbox.fill")
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(GiftPalette.plum)
      }
      .frame(width: 104, height: 112)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.productName)
            .font(.headline)
          Spacer()
          Menu {
            ForEach(WishlistItemStatus.allCases, id: \.self) { status in
              Button(status.displayName) { setStatus(status) }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
              .font(.title3)
          }
          .accessibilityLabel("Change status for \(item.productName)")
        }

        if let retailerName = item.retailerName {
          Text(retailerName)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        if let variant = item.variant {
          Label(variant, systemImage: "tag")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        HStack {
          Text(item.status.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(item.status == .wanted ? GiftPalette.sage : .secondary)
          Spacer()
          if let estimatedPrice = item.estimatedPrice, let currency = item.currency {
            Text("\(currency) \(estimatedPrice.formatted())")
              .font(.subheadline.weight(.semibold))
          }
        }
      }
    }
    .padding(14)
    .giftCard()
    .accessibilityElement(children: .contain)
  }
}
