import Combine
import Foundation
import WishlistCore

@MainActor
final class AppModel: ObservableObject {
  enum LoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
  }

  @Published private(set) var loadState: LoadState = .idle
  @Published private(set) var allowsLocalMutations = false
  @Published private(set) var wishlists: [Wishlist] = []
  @Published private(set) var itemsByWishlist: [UUID: [WishlistItem]] = [:]

  func load() async {
    guard loadState == .idle else { return }
    loadState = .loading
    await Task.yield()

    #if DEBUG
      let preview = DevelopmentSampleData.make()
      wishlists = preview.wishlists
      itemsByWishlist = preview.itemsByWishlist
      allowsLocalMutations = true
      loadState = .loaded
    #else
      do {
        let configuration = try AppConfiguration.load()
        _ = SupabaseClientFactory.make(configuration: configuration)
        loadState = .failed(
          "The secure sign-in flow is the next implementation slice. Use a Debug build for the local UI preview."
        )
      } catch {
        loadState = .failed("Add your local Supabase configuration to run Jiejie.")
      }
    #endif
  }

  func createWishlist(from draft: WishlistDraft) throws {
    guard allowsLocalMutations else {
      throw WishlistError.serviceUnavailable
    }

    if let firstIssue = draft.validationIssues().first {
      throw firstIssue
    }

    let now = Date()
    let wishlist = Wishlist(
      id: UUID(),
      publicSlug: UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(24)
        .description,
      ownerID: DevelopmentSampleData.ownerID,
      name: draft.normalizedName,
      description: draft.description,
      type: draft.type,
      eventDate: draft.eventDate,
      visibility: draft.visibility,
      position: Int64(wishlists.count),
      createdAt: now,
      updatedAt: now
    )
    wishlists.append(wishlist)
    itemsByWishlist[wishlist.id] = []
  }

  func archiveWishlist(id: UUID) {
    guard let index = wishlists.firstIndex(where: { $0.id == id }) else { return }
    wishlists[index].state = .archived
    wishlists[index].updatedAt = Date()
  }

  func setItemStatus(itemID: UUID, in wishlistID: UUID, status: WishlistItemStatus) {
    guard let index = itemsByWishlist[wishlistID]?.firstIndex(where: { $0.id == itemID }) else {
      return
    }
    itemsByWishlist[wishlistID]?[index].status = status
    itemsByWishlist[wishlistID]?[index].updatedAt = Date()
  }

  func wishlist(id: UUID) -> Wishlist? {
    wishlists.first { $0.id == id }
  }

  func items(in wishlistID: UUID) -> [WishlistItem] {
    itemsByWishlist[wishlistID, default: []]
  }
}

private enum DevelopmentSampleData {
  static let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

  static func make() -> (wishlists: [Wishlist], itemsByWishlist: [UUID: [WishlistItem]]) {
    let birthdayID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let ongoingID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    let now = Date()
    let calendar = Calendar(identifier: .gregorian)
    let eventDate = calendar.date(byAdding: .day, value: 45, to: now)

    let birthday = Wishlist(
      id: birthdayID,
      publicSlug: "200000000000000000000001",
      ownerID: ownerID,
      name: "Thirty & thriving",
      description: "A few things for a cosy birthday weekend.",
      type: .birthday,
      eventDate: eventDate,
      visibility: .linkOnly,
      position: 0,
      createdAt: now,
      updatedAt: now
    )
    let ongoing = Wishlist(
      id: ongoingID,
      publicSlug: "200000000000000000000002",
      ownerID: ownerID,
      name: "Things I want",
      description: "An always-on list of considered favourites.",
      type: .ongoing,
      visibility: .public,
      position: 1,
      createdAt: now,
      updatedAt: now
    )

    let birthdayItems = [
      WishlistItem(
        id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
        wishlistID: birthdayID,
        productName: "Hand-thrown ramen bowls",
        description: "A pair in the deep ocean glaze.",
        retailerName: "Sample Ceramics",
        estimatedPrice: 88,
        currency: "AUD",
        desiredQuantity: 2,
        variant: "Ocean glaze",
        priority: .high,
        category: "Home",
        position: 0,
        createdAt: now,
        updatedAt: now
      ),
      WishlistItem(
        id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
        wishlistID: birthdayID,
        productName: "Linen picnic blanket",
        description: "Large enough for four people.",
        retailerName: "Sample Outdoors",
        estimatedPrice: 149,
        currency: "AUD",
        variant: "Sage stripe",
        priority: .normal,
        category: "Outdoors",
        position: 1,
        createdAt: now,
        updatedAt: now
      ),
    ]
    let ongoingItems = [
      WishlistItem(
        id: UUID(uuidString: "40000000-0000-0000-0000-000000000003")!,
        wishlistID: ongoingID,
        productName: "Compact instant camera",
        description: "For weekends away; any neutral colour.",
        retailerName: "Sample Camera Shop",
        estimatedPrice: 179.95,
        currency: "AUD",
        priority: .mustHave,
        category: "Tech",
        createdAt: now,
        updatedAt: now
      )
    ]

    return (
      [birthday, ongoing],
      [birthdayID: birthdayItems, ongoingID: ongoingItems]
    )
  }
}
