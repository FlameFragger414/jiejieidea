import Combine
import Foundation
import WishlistCore

/// Wishlist content for the signed-in person.
///
/// Wishlist persistence arrives in the next vertical slice. Until then the model reports an honest
/// empty state, and the in-memory sample content is only reachable in the explicitly selected
/// development mode described by `DevelopmentMode`.
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

  private let usesSampleData: Bool

  init(usesSampleData: Bool = DevelopmentMode.sampleDataEnabled) {
    self.usesSampleData = usesSampleData
  }

  func load() async {
    guard loadState == .idle else { return }
    loadState = .loading
    await Task.yield()

    if usesSampleData {
      let sample = SampleWishlistData.make()
      wishlists = sample.wishlists
      itemsByWishlist = sample.itemsByWishlist
      allowsLocalMutations = true
    }

    loadState = .loaded
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
      ownerID: SampleWishlistData.ownerID,
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

/// Opt-in development switches.
///
/// An ordinary Debug run behaves like a release build. Sample content appears only when the launch
/// argument `-JiejieSampleData` or the environment variable `JIEJIE_SAMPLE_DATA=1` is set, and in
/// SwiftUI previews.
enum DevelopmentMode {
  static let sampleDataLaunchArgument = "-JiejieSampleData"

  static var sampleDataEnabled: Bool {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains(sampleDataLaunchArgument) {
        return true
      }
      return ProcessInfo.processInfo.environment["JIEJIE_SAMPLE_DATA"] == "1"
    #else
      return false
    #endif
  }
}
