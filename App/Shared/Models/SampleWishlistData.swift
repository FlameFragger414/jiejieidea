import Foundation
import WishlistCore

/// Fictional content for SwiftUI previews and the opt-in development mode.
///
/// It is never loaded during an ordinary run, including Debug runs. See `DevelopmentMode`.
enum SampleWishlistData {
  static let ownerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!

  static func profile(onboardingCompleted: Bool = true) -> UserProfile {
    UserProfile(
      id: ownerID,
      displayName: onboardingCompleted ? "Mia Chen" : UserProfile.seededDisplayName,
      onboardingCompleted: onboardingCompleted,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

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
