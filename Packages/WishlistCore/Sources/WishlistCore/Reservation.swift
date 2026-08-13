import Foundation

public enum GiftReservationStatus: String, Codable, CaseIterable, Sendable {
  case reserved
  case purchased
  case cancelled
  case unavailable

  public var holdsCapacity: Bool {
    self == .reserved || self == .purchased
  }
}

public struct GiftReservation: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let itemID: UUID
  public let quantity: Int
  public let status: GiftReservationStatus
  public let privateNote: String?
  public let createdAt: Date
  public let updatedAt: Date

  public init(
    id: UUID,
    itemID: UUID,
    quantity: Int,
    status: GiftReservationStatus,
    privateNote: String? = nil,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.itemID = itemID
    self.quantity = quantity
    self.status = status
    self.privateNote = privateNote
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id = "reservation_id"
    case itemID = "item_id"
    case quantity
    case status
    case privateNote = "private_note"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

public struct ItemAvailability: Equatable, Sendable {
  public let desiredQuantity: Int
  public let activeReservedQuantity: Int

  public init(desiredQuantity: Int, activeReservedQuantity: Int) throws {
    guard desiredQuantity > 0 else {
      throw ValidationIssue(field: "desiredQuantity", message: "Desired quantity must be positive.")
    }
    guard activeReservedQuantity >= 0 else {
      throw ValidationIssue(
        field: "reservedQuantity", message: "Reserved quantity cannot be negative.")
    }
    guard activeReservedQuantity <= desiredQuantity else {
      throw ValidationIssue(
        field: "reservedQuantity", message: "Reserved quantity exceeds the requested quantity.")
    }

    self.desiredQuantity = desiredQuantity
    self.activeReservedQuantity = activeReservedQuantity
  }

  public var remainingQuantity: Int {
    desiredQuantity - activeReservedQuantity
  }

  public var isAvailable: Bool {
    remainingQuantity > 0
  }

  public func canReserve(_ quantity: Int) -> Bool {
    quantity > 0 && quantity <= remainingQuantity
  }
}

public struct ReservationRequest: Codable, Equatable, Sendable {
  public let itemID: UUID
  public let quantity: Int
  public let privateNote: String?
  public let idempotencyKey: UUID
  public let shareToken: String?

  public init(
    itemID: UUID,
    quantity: Int,
    privateNote: String? = nil,
    idempotencyKey: UUID = UUID(),
    shareToken: String? = nil
  ) throws {
    guard (1...999).contains(quantity) else {
      throw ValidationIssue(
        field: "quantity", message: "Choose a reservation quantity from 1 to 999.")
    }
    guard privateNote?.count ?? 0 <= 1_000 else {
      throw ValidationIssue(
        field: "privateNote", message: "Keep the private note to 1,000 characters or fewer.")
    }

    self.itemID = itemID
    self.quantity = quantity
    self.privateNote = privateNote?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.idempotencyKey = idempotencyKey
    self.shareToken = shareToken
  }

  private enum CodingKeys: String, CodingKey {
    case itemID = "p_item_id"
    case quantity = "p_quantity"
    case privateNote = "p_private_note"
    case idempotencyKey = "p_idempotency_key"
    case shareToken = "p_share_token"
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
