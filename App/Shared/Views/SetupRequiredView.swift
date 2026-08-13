import SwiftUI

struct SetupRequiredView: View {
  let message: String

  var body: some View {
    EmptyStateView(
      title: "Configuration needed",
      systemImage: "gift.fill",
      description:
        "\(message) Copy the example xcconfig files and add a Supabase URL, publishable key, and share-link host."
    )
  }
}
