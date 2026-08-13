import SwiftUI

struct EmptyStateView: View {
  let title: String
  let systemImage: String
  let description: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: systemImage)
        .font(.system(size: 38, weight: .semibold))
        .foregroundStyle(GiftPalette.plum)
        .frame(width: 78, height: 78)
        .background(GiftPalette.blush.opacity(0.28), in: Circle())
        .accessibilityHidden(true)
      VStack(spacing: 6) {
        Text(title)
          .font(.system(.title2, design: .rounded, weight: .bold))
        Text(description)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 440)
      }
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }
}
