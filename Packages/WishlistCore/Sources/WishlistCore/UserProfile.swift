import Foundation

/// A person's own profile row.
///
/// Row Level Security limits `public.profiles` reads to the signed-in owner, so this type is only
/// ever populated with the caller's own record.
public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
  /// The display name written by `private.handle_new_user` when no provider name was supplied.
  ///
  /// Onboarding treats it as "not chosen yet" instead of pre-filling it as the person's own words.
  /// It must stay in sync with `supabase/migrations/20260813010000_initial_mvp_foundation.sql`.
  public static let seededDisplayName = "New member"

  public let id: UUID
  public var displayName: String
  public var avatarPath: String?
  public var onboardingCompleted: Bool
  public let createdAt: Date
  public var updatedAt: Date

  public init(
    id: UUID,
    displayName: String,
    avatarPath: String? = nil,
    onboardingCompleted: Bool = false,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.displayName = displayName
    self.avatarPath = avatarPath
    self.onboardingCompleted = onboardingCompleted
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// `true` when the person has replaced the seeded name with one of their own.
  public var hasChosenDisplayName: Bool {
    displayName != Self.seededDisplayName
      && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The value onboarding should pre-fill, which is empty until a real name exists.
  public var editableDisplayName: String {
    hasChosenDisplayName ? displayName : ""
  }

  public var requiresOnboarding: Bool {
    !onboardingCompleted
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case avatarPath = "avatar_path"
    case onboardingCompleted = "onboarding_completed"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

/// The shape returned by the profile mutation functions in `public`.
///
/// `replacedAvatarPath` lets the client delete the storage object it just replaced without needing a
/// second read, and without the database deleting objects it cannot physically remove.
public struct ProfileMutationResult: Codable, Equatable, Sendable {
  public let id: UUID
  public let displayName: String
  public let avatarPath: String?
  public let onboardingCompleted: Bool
  public let createdAt: Date
  public let updatedAt: Date
  public let replacedAvatarPath: String?

  public init(
    id: UUID,
    displayName: String,
    avatarPath: String? = nil,
    onboardingCompleted: Bool,
    createdAt: Date,
    updatedAt: Date,
    replacedAvatarPath: String? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.avatarPath = avatarPath
    self.onboardingCompleted = onboardingCompleted
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.replacedAvatarPath = replacedAvatarPath
  }

  public var profile: UserProfile {
    UserProfile(
      id: id,
      displayName: displayName,
      avatarPath: avatarPath,
      onboardingCompleted: onboardingCompleted,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case avatarPath = "avatar_path"
    case onboardingCompleted = "onboarding_completed"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case replacedAvatarPath = "replaced_avatar_path"
  }
}

/// Editable profile fields with validation matching the `profiles` table constraints.
public struct ProfileDraft: Equatable, Sendable {
  public static let maximumDisplayNameLength = 80

  public var displayName: String

  public init(displayName: String = "") {
    self.displayName = displayName
  }

  public init(profile: UserProfile) {
    displayName = profile.editableDisplayName
  }

  /// Trimmed, with internal whitespace runs collapsed so "Mia   Chen" is stored as "Mia Chen".
  public var normalizedDisplayName: String {
    displayName
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  public func validationIssues() -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    let normalized = normalizedDisplayName

    if normalized.isEmpty {
      issues.append(
        ValidationIssue(field: "displayName", message: "Enter the name friends will recognise.")
      )
    } else if normalized.count > Self.maximumDisplayNameLength {
      issues.append(
        ValidationIssue(
          field: "displayName",
          message: "Keep your name to \(Self.maximumDisplayNameLength) characters or fewer."
        )
      )
    } else if normalized.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
      issues.append(
        ValidationIssue(field: "displayName", message: "Remove special control characters.")
      )
    }

    return issues
  }

  public var isValid: Bool {
    validationIssues().isEmpty
  }
}
