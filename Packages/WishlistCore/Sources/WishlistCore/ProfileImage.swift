import Foundation

/// Image formats the `profile-images` bucket accepts.
///
/// The list mirrors the bucket's `allowed_mime_types` and the filename check in
/// `private.is_own_profile_image`. Adding a format requires a new migration as well.
public enum ProfileImageFormat: String, CaseIterable, Sendable {
  case jpeg
  case png
  case heic
  case webp

  public var fileExtension: String {
    switch self {
    case .jpeg: "jpg"
    case .png: "png"
    case .heic: "heic"
    case .webp: "webp"
    }
  }

  public var mimeType: String {
    switch self {
    case .jpeg: "image/jpeg"
    case .png: "image/png"
    case .heic: "image/heic"
    case .webp: "image/webp"
    }
  }

  public static func named(fileExtension: String) -> ProfileImageFormat? {
    let normalized = fileExtension.lowercased()
    return allCases.first { $0.fileExtension == normalized }
  }

  /// Identifies the format from the leading bytes instead of trusting a caller-supplied MIME type.
  public static func detected(in data: Data) -> ProfileImageFormat? {
    let bytes = [UInt8](data.prefix(16))
    guard bytes.count >= 12 else { return nil }

    if bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
      return .jpeg
    }
    if Array(bytes[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
      return .png
    }
    if Array(bytes[0..<4]) == Array("RIFF".utf8), Array(bytes[8..<12]) == Array("WEBP".utf8) {
      return .webp
    }
    if Array(bytes[4..<8]) == Array("ftyp".utf8) {
      let brand = String(decoding: bytes[8..<12])
      if ["heic", "heix", "hevc", "heim", "heis", "hevm", "hevs", "mif1", "msf1"].contains(brand) {
        return .heic
      }
    }
    return nil
  }
}

/// A validated profile-image upload.
///
/// The object name is always derived from the signed-in user's ID, so a caller cannot aim an upload
/// at somebody else's folder. `private.is_own_profile_image` enforces the same shape in PostgreSQL,
/// which is the boundary that actually protects the bucket.
public struct ProfileImageUpload: Equatable, Sendable {
  public static let maximumByteCount = 5 * 1024 * 1024

  public let ownerID: UUID
  public let format: ProfileImageFormat
  public let data: Data
  public let objectName: String

  /// - Throws: `ValidationIssue` when the payload is empty, too large, or not a supported image.
  public init(ownerID: UUID, data: Data, identifier: UUID = UUID()) throws {
    guard !data.isEmpty else {
      throw ValidationIssue(field: "profileImage", message: "Choose an image to upload.")
    }
    guard data.count <= Self.maximumByteCount else {
      throw ValidationIssue(
        field: "profileImage",
        message: "Choose an image smaller than 5 MB."
      )
    }
    guard let format = ProfileImageFormat.detected(in: data) else {
      throw ValidationIssue(
        field: "profileImage",
        message: "Choose a JPEG, PNG, HEIC, or WebP image."
      )
    }

    self.ownerID = ownerID
    self.format = format
    self.data = data
    objectName = ProfileImageObject.name(
      ownerID: ownerID,
      format: format,
      identifier: identifier
    )
  }

  public var contentType: String {
    format.mimeType
  }
}

/// Builds and validates `profile-images` object names.
public enum ProfileImageObject {
  public static let bucket = "profile-images"

  public static func name(ownerID: UUID, format: ProfileImageFormat, identifier: UUID) -> String {
    "\(ownerID.uuidString.lowercased())/\(identifier.uuidString.lowercased()).\(format.fileExtension)"
  }

  /// `true` when `objectName` is exactly `<ownerID>/<uuid>.<supported extension>`.
  public static func isOwned(_ objectName: String, by ownerID: UUID) -> Bool {
    guard let components = split(objectName) else { return false }
    return components.folder == ownerID.uuidString.lowercased()
  }

  /// The owner encoded in the object name, or `nil` when the name is malformed.
  public static func owner(of objectName: String) -> UUID? {
    guard let components = split(objectName) else { return nil }
    return UUID(uuidString: components.folder)
  }

  private static func split(_ objectName: String) -> (folder: String, file: String)? {
    let segments = objectName.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.count == 2 else { return nil }

    let folder = String(segments[0]).lowercased()
    let file = String(segments[1]).lowercased()
    guard UUID(uuidString: folder) != nil else { return nil }

    let fileSegments = file.split(separator: ".", omittingEmptySubsequences: false)
    guard fileSegments.count == 2,
      UUID(uuidString: String(fileSegments[0])) != nil,
      ProfileImageFormat.named(fileExtension: String(fileSegments[1])) != nil
    else {
      return nil
    }

    return (folder, file)
  }
}

extension String {
  fileprivate init(decoding bytes: ArraySlice<UInt8>) {
    self = String(decoding: Array(bytes), as: UTF8.self)
  }
}
