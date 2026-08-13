import SwiftUI
import WishlistCore

struct WishlistDashboardView: View {
  @EnvironmentObject private var model: AppModel
  @State private var isCreatingWishlist = false

  private let columns = [
    GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 18)
  ]

  var body: some View {
    Group {
      switch model.loadState {
      case .idle, .loading:
        ProgressView("Unwrapping your wishlists…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .failed(let message):
        SetupRequiredView(message: message)
      case .loaded where activeWishlists.isEmpty:
        EmptyStateView(
          title: "A fresh sheet of wrapping paper",
          systemImage: "gift",
          description: "Create a wishlist for an occasion—or keep one going all year.",
          actionTitle: model.allowsLocalMutations ? "Create a wishlist" : nil,
          action: model.allowsLocalMutations ? { isCreatingWishlist = true } : nil
        )
      case .loaded:
        dashboard
      }
    }
    .navigationTitle("Your wishlists")
    .toolbar {
      if model.allowsLocalMutations {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isCreatingWishlist = true
          } label: {
            Label("New wishlist", systemImage: "plus")
          }
          .keyboardShortcut("n", modifiers: .command)
        }
      }
    }
    .sheet(isPresented: $isCreatingWishlist) {
      WishlistEditorView()
        .environmentObject(model)
    }
    .task {
      await model.load()
    }
    .onReceive(NotificationCenter.default.publisher(for: .newWishlistRequested)) { _ in
      if model.allowsLocalMutations {
        isCreatingWishlist = true
      }
    }
  }

  private var activeWishlists: [Wishlist] {
    model.wishlists.filter { $0.state == .active }
  }

  private var dashboard: some View {
    ScrollView {
      LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
        ForEach(activeWishlists) { wishlist in
          NavigationLink {
            WishlistDetailView(wishlistID: wishlist.id)
          } label: {
            WishlistCard(
              wishlist: wishlist,
              itemCount: model.items(in: wishlist.id).count
            )
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("Archive wishlist", role: .destructive) {
              model.archiveWishlist(id: wishlist.id)
            }
          }
        }
      }
      .padding(20)
    }
    .background(GiftPalette.canvas)
    .safeAreaInset(edge: .top, spacing: 0) {
      DevelopmentPreviewBanner()
    }
  }
}

private struct WishlistCard: View {
  let wishlist: Wishlist
  let itemCount: Int

  var body: some View {
    HStack(spacing: 0) {
      LinearGradient(
        colors: accentColors,
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(width: 10)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          Image(systemName: symbolName)
            .font(.title2.weight(.semibold))
            .foregroundStyle(accentColors[0])
            .frame(width: 42, height: 42)
            .background(accentColors[0].opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)

          Spacer()
          PrivacySeal(compact: true)
        }

        VStack(alignment: .leading, spacing: 5) {
          Text(wishlist.name)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(2)
          Text(wishlist.description.isEmpty ? wishlist.type.displayName : wishlist.description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        HStack {
          Label("\(itemCount) \(itemCount == 1 ? "gift" : "gifts")", systemImage: "sparkles")
          Spacer()
          Text(wishlist.visibility.displayName)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
      }
      .padding(18)
    }
    .frame(minHeight: 210, alignment: .top)
    .giftCard()
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens the wishlist")
  }

  private var symbolName: String {
    switch wishlist.type {
    case .birthday: "birthday.cake.fill"
    case .wedding: "heart.fill"
    case .christmas: "snowflake"
    case .babyShower: "figure.and.child.holdinghands"
    case .graduation: "graduationcap.fill"
    case .ongoing: "star.fill"
    case .other: "gift.fill"
    }
  }

  private var accentColors: [Color] {
    switch wishlist.type {
    case .birthday: [GiftPalette.berry, GiftPalette.plum]
    case .ongoing: [GiftPalette.sage, GiftPalette.plum]
    default: [GiftPalette.gold, GiftPalette.berry]
    }
  }
}

extension Notification.Name {
  static let newWishlistRequested = Notification.Name("NewWishlistRequested")
}
