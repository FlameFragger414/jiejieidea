import SwiftUI
import WishlistCore

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

/// Renders the profile image, or initials while none exists.
struct ProfileAvatarView: View {
  let displayName: String
  let state: ProfileModel.AvatarState
  var diameter: CGFloat = 96

  var body: some View {
    ZStack {
      Circle()
        .fill(GiftPalette.blush.opacity(0.32))

      if let image = state.imageData.flatMap(Image.init(profileImageData:)) {
        image
          .resizable()
          .scaledToFill()
      } else if state.isBusy {
        ProgressView()
      } else {
        Text(initials)
          .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
          .foregroundStyle(GiftPalette.plum)
      }
    }
    .frame(width: diameter, height: diameter)
    .clipShape(Circle())
    .overlay {
      Circle().stroke(.primary.opacity(0.08), lineWidth: 1)
    }
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    switch state {
    case .loading:
      "Loading profile photo"
    case .uploading:
      "Updating profile photo"
    case .ready:
      "Profile photo"
    case .empty, .failed:
      "No profile photo"
    }
  }

  private var initials: String {
    let words =
      displayName
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
    let letters = words.prefix(2).compactMap(\.first)
    return letters.isEmpty ? "?" : String(letters).uppercased()
  }
}

extension Image {
  /// Decodes downloaded avatar bytes for display, returning `nil` when they are not an image.
  init?(profileImageData data: Data) {
    #if canImport(UIKit)
      guard let image = UIImage(data: data) else { return nil }
      self.init(uiImage: image)
    #elseif canImport(AppKit)
      guard let image = NSImage(data: data) else { return nil }
      self.init(nsImage: image)
    #else
      return nil
    #endif
  }
}
