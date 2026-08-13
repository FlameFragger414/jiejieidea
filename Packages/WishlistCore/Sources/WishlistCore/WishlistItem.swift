import Foundation

public enum WishlistItemStatus: String, Codable, CaseIterable, Sendable {
  case wanted
  case purchasedByOwner = "purchased_by_owner"
  case received
  case noLongerWanted = "no_longer_wanted"

  public var canBeReserved: Bool { self == .wanted }

  public var displayName: String {
    switch self {
    case .wanted: "Wanted"
    case .purchasedByOwner: "Purchased by me"
    case .received: "Received"
    case .noLongerWanted: "No longer wanted"
    }
  }
}

public enum WishlistItemPriority: String, Codable, CaseIterable, Sendable {
  case low
  case normal
  case high
  case mustHave = "must_have"

  public var displayName: String {
    switch self {
    case .low: "Nice to have"
    case .normal: "Would love"
    case .high: "High priority"
    case .mustHave: "Most wanted"
    }
  }
}

public struct Money: Codable, Equatable, Sendable {
  public let amount: Decimal
  public let currencyCode: String

  public init(amount: Decimal, currencyCode: String) throws {
    let normalizedCurrency = currencyCode.uppercased()
    guard amount >= 0 else {
      throw ValidationIssue(field: "estimatedPrice", message: "Enter a price of zero or more.")
    }
    guard normalizedCurrency.count == 3,
      normalizedCurrency.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) })
    else {
      throw ValidationIssue(field: "currency", message: "Choose a valid three-letter currency.")
    }
    self.amount = amount
    self.currencyCode = normalizedCurrency
  }
}

public struct WishlistItem: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let wishlistID: UUID
  public var productName: String
  public var description: String
  public var imagePath: String?
  public var productURL: URL?
  public var retailerName: String?
  public var estimatedPrice: Decimal?
  public var currency: String?
  public var desiredQuantity: Int
  public var variant: String?
  public var priority: WishlistItemPriority
  public var category: String?
  public var position: Int64
  public var status: WishlistItemStatus
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID,
    wishlistID: UUID,
    productName: String,
    description: String = "",
    imagePath: String? = nil,
    productURL: URL? = nil,
    retailerName: String? = nil,
    estimatedPrice: Decimal? = nil,
    currency: String? = nil,
    desiredQuantity: Int = 1,
    variant: String? = nil,
    priority: WishlistItemPriority = .normal,
    category: String? = nil,
    position: Int64 = 0,
    status: WishlistItemStatus = .wanted,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.wishlistID = wishlistID
    self.productName = productName
    self.description = description
    self.imagePath = imagePath
    self.productURL = productURL
    self.retailerName = retailerName
    self.estimatedPrice = estimatedPrice
    self.currency = currency
    self.desiredQuantity = desiredQuantity
    self.variant = variant
    self.priority = priority
    self.category = category
    self.position = position
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case wishlistID = "wishlist_id"
    case productName = "product_name"
    case description
    case imagePath = "image_path"
    case productURL = "product_url"
    case retailerName = "retailer_name"
    case estimatedPrice = "estimated_price"
    case currency
    case desiredQuantity = "desired_quantity"
    case variant
    case priority
    case category
    case position
    case status
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

public struct WishlistItemDraft: Equatable, Sendable {
  public var productName: String
  public var description: String
  public var imagePath: String?
  public var productURLText: String
  public var retailerName: String
  public var estimatedPrice: Decimal?
  public var currency: String
  public var desiredQuantity: Int
  public var variant: String
  public var priority: WishlistItemPriority
  public var category: String

  public init(
    productName: String = "",
    description: String = "",
    imagePath: String? = nil,
    productURLText: String = "",
    retailerName: String = "",
    estimatedPrice: Decimal? = nil,
    currency: String = "AUD",
    desiredQuantity: Int = 1,
    variant: String = "",
    priority: WishlistItemPriority = .normal,
    category: String = ""
  ) {
    self.productName = productName
    self.description = description
    self.imagePath = imagePath
    self.productURLText = productURLText
    self.retailerName = retailerName
    self.estimatedPrice = estimatedPrice
    self.currency = currency
    self.desiredQuantity = desiredQuantity
    self.variant = variant
    self.priority = priority
    self.category = category
  }

  public func validationIssues() -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    let trimmedName = productName.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedName.isEmpty {
      issues.append(ValidationIssue(field: "productName", message: "Enter a product name."))
    } else if trimmedName.count > 200 {
      issues.append(
        ValidationIssue(
          field: "productName", message: "Keep the product name to 200 characters or fewer."))
    }

    if description.count > 4_000 {
      issues.append(
        ValidationIssue(
          field: "description", message: "Keep the note to 4,000 characters or fewer."))
    }

    if !(1...999).contains(desiredQuantity) {
      issues.append(
        ValidationIssue(field: "desiredQuantity", message: "Choose a quantity from 1 to 999."))
    }

    let trimmedURL = productURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedURL.isEmpty {
      let url = URL(string: trimmedURL)
      let scheme = url?.scheme?.lowercased()
      if !["http", "https"].contains(scheme ?? "") || url?.host == nil {
        issues.append(
          ValidationIssue(
            field: "productURL", message: "Enter a complete http or https product link."))
      }
    }

    if let estimatedPrice {
      do {
        _ = try Money(amount: estimatedPrice, currencyCode: currency)
      } catch let issue as ValidationIssue {
        issues.append(issue)
      } catch {
        issues.append(ValidationIssue(field: "estimatedPrice", message: "Enter a valid price."))
      }
    }

    return issues
  }
}
