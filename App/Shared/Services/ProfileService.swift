import Foundation
import Supabase
import WishlistCore

/// A profile failure that either belongs beside a field or beside the screen.
enum ProfileServiceError: Error, Equatable, Sendable {
  case validation(ValidationIssue)
  case authentication(AuthenticationFailure)

  var userMessage: String {
    switch self {
    case .validation(let issue): issue.message
    case .authentication(let failure): failure.userMessage
    }
  }

  var validationIssue: ValidationIssue? {
    if case .validation(let issue) = self { return issue }
    return nil
  }

  var authenticationFailure: AuthenticationFailure? {
    if case .authentication(let failure) = self { return failure }
    return nil
  }
}

/// Profile reads, writes, avatar storage, and account deletion.
protocol ProfileService: Sendable {
  func loadProfile(userID: UUID) async throws -> UserProfile
  func saveProfile(_ draft: ProfileDraft, completingOnboarding: Bool) async throws -> UserProfile
  func uploadAvatar(_ upload: ProfileImageUpload) async throws -> UserProfile
  func removeAvatar() async throws -> UserProfile
  /// Downloads a private avatar object through the authenticated storage API.
  func avatarData(path: String) async throws -> Data
  func deleteAccount() async throws
}

struct SupabaseProfileService: ProfileService {
  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  func loadProfile(userID: UUID) async throws -> UserProfile {
    do {
      return
        try await client
        .from("profiles")
        .select("id,display_name,avatar_path,onboarding_completed,created_at,updated_at")
        .eq("id", value: userID)
        .single()
        .execute()
        .value
    } catch {
      throw ProfileFailureMapping.error(for: error)
    }
  }

  func saveProfile(_ draft: ProfileDraft, completingOnboarding: Bool) async throws -> UserProfile {
    if let issue = draft.validationIssues().first {
      throw ProfileServiceError.validation(issue)
    }

    return try await mutate(
      "save_my_profile",
      parameters: [
        "p_display_name": AnyJSON.string(draft.normalizedDisplayName),
        "p_complete_onboarding": AnyJSON.bool(completingOnboarding),
      ]
    ).profile
  }

  func uploadAvatar(_ upload: ProfileImageUpload) async throws -> UserProfile {
    do {
      try await client.storage
        .from(ProfileImageObject.bucket)
        .upload(
          upload.objectName,
          data: upload.data,
          options: FileOptions(contentType: upload.contentType, upsert: false)
        )
    } catch {
      throw ProfileFailureMapping.error(for: error)
    }

    let result: ProfileMutationResult
    do {
      result = try await mutate(
        "set_my_profile_avatar",
        parameters: ["p_object_name": AnyJSON.string(upload.objectName)]
      )
    } catch {
      // The object exists but the profile still points elsewhere, so remove the orphan rather than
      // leaving an unreferenced image in the bucket.
      await discardObject(named: upload.objectName)
      throw error
    }

    await removeReplacedObject(in: result)
    return result.profile
  }

  func removeAvatar() async throws -> UserProfile {
    let result = try await mutate("clear_my_profile_avatar", parameters: [:])
    await removeReplacedObject(in: result)
    return result.profile
  }

  /// Avatars are fetched with the caller's own credentials rather than a signed URL, so no
  /// shareable link to a private object is ever created.
  func avatarData(path: String) async throws -> Data {
    do {
      return try await client.storage.from(ProfileImageObject.bucket).download(path: path)
    } catch {
      throw ProfileFailureMapping.error(for: error)
    }
  }

  /// Deletes the account through the `delete-account` Edge Function.
  ///
  /// The function reads the caller from the verified JWT, so no identifier is sent in the body.
  /// Removing the auth user requires the service-role key, which exists only in the function's
  /// server-side environment.
  func deleteAccount() async throws {
    do {
      try await client.functions.invoke(
        "delete-account",
        options: FunctionInvokeOptions(method: .post)
      )
    } catch {
      throw ProfileFailureMapping.error(for: error)
    }
  }

  private func mutate(
    _ function: String,
    parameters: [String: AnyJSON]
  ) async throws -> ProfileMutationResult {
    do {
      return
        try await client
        .rpc(function, params: parameters)
        .single()
        .execute()
        .value
    } catch {
      throw ProfileFailureMapping.error(for: error)
    }
  }

  private func removeReplacedObject(in result: ProfileMutationResult) async {
    guard let replaced = result.replacedAvatarPath, replaced != result.avatarPath else { return }
    await discardObject(named: replaced)
  }

  /// Best-effort cleanup. A failure here leaves an unreferenced private object that only its owner
  /// can read, so it is not worth surfacing or retrying in the interface.
  private func discardObject(named objectName: String) async {
    _ = try? await client.storage.from(ProfileImageObject.bucket).remove(paths: [objectName])
  }
}

/// Maps PostgREST, storage, and Edge Function errors onto field or screen level failures.
enum ProfileFailureMapping {
  static func error(for error: any Error) -> ProfileServiceError {
    if let profileError = error as? ProfileServiceError {
      return profileError
    }

    if let postgrestError = error as? PostgrestError,
      let mapped = mapped(rawMessage: postgrestError.message)
    {
      return mapped
    }

    return .authentication(AuthenticationFailureMapping.failure(for: error))
  }

  /// The stable messages raised by the profile functions. They are identifiers, not server text,
  /// so matching on them does not leak database detail into the interface.
  private static func mapped(rawMessage: String) -> ProfileServiceError? {
    switch rawMessage {
    case "display_name_required":
      .validation(
        ValidationIssue(field: "displayName", message: "Enter the name friends will recognise.")
      )
    case "display_name_too_long":
      .validation(
        ValidationIssue(
          field: "displayName",
          message: "Keep your name to \(ProfileDraft.maximumDisplayNameLength) characters or fewer."
        )
      )
    case "avatar_not_owned", "avatar_object_missing":
      .validation(
        ValidationIssue(
          field: "profileImage",
          message: "That image could not be attached to your profile. Choose it again."
        )
      )
    case "authentication_required":
      .authentication(.notSignedIn)
    case "profile_not_found":
      .authentication(.sessionExpired)
    default:
      nil
    }
  }
}
