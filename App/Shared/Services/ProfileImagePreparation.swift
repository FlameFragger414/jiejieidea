import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WishlistCore

/// Downscales and re-encodes a picked image before it leaves the device.
///
/// Re-encoding keeps every upload comfortably below the bucket's size ceiling and drops the
/// original metadata, including any location recorded by the camera.
enum ProfileImagePreparation {
  static let maximumPixelDimension = 1_024
  static let compressionQuality = 0.85

  static func prepared(_ data: Data) throws -> Data {
    guard !data.isEmpty else {
      throw ValidationIssue(field: "profileImage", message: "Choose an image to upload.")
    }
    guard ProfileImageFormat.detected(in: data) != nil,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0
    else {
      throw ValidationIssue(
        field: "profileImage",
        message: "Choose a JPEG, PNG, HEIC, or WebP image."
      )
    }

    let thumbnailOptions =
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
      ] as CFDictionary

    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
      throw ValidationIssue(
        field: "profileImage",
        message: "That image could not be prepared. Choose another one."
      )
    }

    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      throw ValidationIssue(
        field: "profileImage",
        message: "That image could not be prepared. Choose another one."
      )
    }

    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
    )

    guard CGImageDestinationFinalize(destination) else {
      throw ValidationIssue(
        field: "profileImage",
        message: "That image could not be prepared. Choose another one."
      )
    }

    return output as Data
  }
}
