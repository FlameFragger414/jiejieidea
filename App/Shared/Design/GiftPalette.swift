import SwiftUI

enum GiftPalette {
  static let plum = Color(red: 0.42, green: 0.18, blue: 0.37)
  static let berry = Color(red: 0.72, green: 0.25, blue: 0.38)
  static let blush = Color(red: 0.96, green: 0.78, blue: 0.78)
  static let sage = Color(red: 0.48, green: 0.60, blue: 0.51)
  static let gold = Color(red: 0.82, green: 0.61, blue: 0.26)

  static var canvas: Color {
    #if os(iOS)
      Color(uiColor: .systemGroupedBackground)
    #elseif os(macOS)
      Color(nsColor: .windowBackgroundColor)
    #else
      Color.clear
    #endif
  }

  static var surface: Color {
    #if os(iOS)
      Color(uiColor: .secondarySystemGroupedBackground)
    #elseif os(macOS)
      Color(nsColor: .controlBackgroundColor)
    #else
      Color.clear
    #endif
  }
}

struct GiftCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .background(GiftPalette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(.primary.opacity(0.08), lineWidth: 1)
      }
      .shadow(color: GiftPalette.plum.opacity(0.08), radius: 14, y: 7)
  }
}

extension View {
  func giftCard() -> some View {
    modifier(GiftCardModifier())
  }
}

struct PrivacySeal: View {
  let compact: Bool

  init(compact: Bool = false) {
    self.compact = compact
  }

  var body: some View {
    Label {
      if !compact {
        Text("Surprise sealed")
      }
    } icon: {
      Image(systemName: "lock.shield.fill")
    }
    .font(.system(compact ? .caption2 : .caption, design: .rounded, weight: .semibold))
    .foregroundStyle(GiftPalette.plum)
    .padding(.horizontal, compact ? 8 : 11)
    .padding(.vertical, compact ? 6 : 8)
    .background(GiftPalette.blush.opacity(0.38), in: Capsule())
    .accessibilityLabel("Reservation privacy is protected")
  }
}

struct DevelopmentPreviewBanner: View {
  var body: some View {
    Label("Development preview · changes stay on this device", systemImage: "hammer.fill")
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(GiftPalette.gold.opacity(0.15))
      .accessibilityAddTraits(.isStaticText)
  }
}
