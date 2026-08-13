import Foundation

public enum WishlistType: String, Codable, CaseIterable, Sendable {
  case birthday
  case wedding
  case christmas
  case babyShower = "baby_shower"
  case graduation
  case ongoing
  case other

  public var displayName: String {
    switch self {
    case .birthday: "Birthday"
    case .wedding: "Wedding"
    case .christmas: "Christmas"
    case .babyShower: "Baby shower"
    case .graduation: "Graduation"
    case .ongoing: "Things I want"
    case .other: "Other"
    }
  }
}

public enum WishlistVisibility: String, Codable, CaseIterable, Sendable {
  case `private`
  case linkOnly = "link_only"
  case `public`

  public var displayName: String {
    switch self {
    case .private: "Private"
    case .linkOnly: "Anyone with the link"
    case .public: "Public"
    }
  }
}

public enum WishlistState: String, Codable, CaseIterable, Sendable {
  case active
  case archived
  case closed
}

public struct Wishlist: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let publicSlug: String
  public let ownerID: UUID
  public var name: String
  public var description: String
  public var type: WishlistType
  public var eventDate: Date?
  public var coverImagePath: String?
  public var visibility: WishlistVisibility
  public var state: WishlistState
  public var position: Int64
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID,
    publicSlug: String,
    ownerID: UUID,
    name: String,
    description: String = "",
    type: WishlistType,
    eventDate: Date? = nil,
    coverImagePath: String? = nil,
    visibility: WishlistVisibility,
    state: WishlistState = .active,
    position: Int64 = 0,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.publicSlug = publicSlug
    self.ownerID = ownerID
    self.name = name
    self.description = description
    self.type = type
    self.eventDate = eventDate
    self.coverImagePath = coverImagePath
    self.visibility = visibility
    self.state = state
    self.position = position
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case publicSlug = "public_slug"
    case ownerID = "owner_id"
    case name
    case description
    case type
    case eventDate = "event_date"
    case coverImagePath = "cover_image_path"
    case visibility
    case state
    case position
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

public struct WishlistDraft: Equatable, Sendable {
  public var name: String
  public var description: String
  public var type: WishlistType
  public var eventDate: Date?
  public var visibility: WishlistVisibility

  public init(
    name: String = "",
    description: String = "",
    type: WishlistType = .ongoing,
    eventDate: Date? = nil,
    visibility: WishlistVisibility = .private
  ) {
    self.name = name
    self.description = description
    self.type = type
    self.eventDate = eventDate
    self.visibility = visibility
  }

  public func validationIssues(calendar: Calendar = .current, now: Date = Date())
    -> [ValidationIssue]
  {
    var issues: [ValidationIssue] = []
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedName.isEmpty {
      issues.append(ValidationIssue(field: "name", message: "Enter a wishlist name."))
    } else if trimmedName.count > 120 {
      issues.append(
        ValidationIssue(
          field: "name", message: "Keep the wishlist name to 120 characters or fewer."))
    }

    if description.count > 2_000 {
      issues.append(
        ValidationIssue(
          field: "description", message: "Keep the description to 2,000 characters or fewer."))
    }

    if let eventDate, calendar.startOfDay(for: eventDate) < calendar.startOfDay(for: now) {
      issues.append(ValidationIssue(field: "eventDate", message: "Choose today or a future date."))
    }

    return issues
  }

  public var normalizedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
