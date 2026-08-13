import SwiftUI
import WishlistCore

struct WishlistEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var model: AppModel
  @State private var draft = WishlistDraft()
  @State private var hasEventDate = false
  @State private var validationMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("The occasion") {
          TextField("Wishlist name", text: $draft.name)
            #if os(iOS)
              .textContentType(.name)
            #endif
            .accessibilityHint("Required, up to 120 characters")
          TextField("Description", text: $draft.description, axis: .vertical)
            .lineLimit(2...5)
          Picker("Type", selection: $draft.type) {
            ForEach(WishlistType.allCases, id: \.self) { type in
              Text(type.displayName).tag(type)
            }
          }
        }

        Section("Timing") {
          Toggle("Add an event date", isOn: $hasEventDate)
          if hasEventDate {
            DatePicker(
              "Event date",
              selection: Binding(
                get: { draft.eventDate ?? Date() },
                set: { draft.eventDate = $0 }
              ),
              displayedComponents: .date
            )
          }
        }

        Section("Who can see it") {
          Picker("Visibility", selection: $draft.visibility) {
            ForEach(WishlistVisibility.allCases, id: \.self) { visibility in
              Text(visibility.displayName).tag(visibility)
            }
          }
          PrivacySeal()
            .listRowBackground(Color.clear)
        }

        if let validationMessage {
          Section {
            Label(validationMessage, systemImage: "exclamationmark.circle.fill")
              .foregroundStyle(.red)
              .accessibilityLabel("Error: \(validationMessage)")
          }
        }
      }
      .navigationTitle("New wishlist")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") { save() }
            .fontWeight(.semibold)
        }
      }
      .onChange(of: hasEventDate) { value in
        if value, draft.eventDate == nil {
          draft.eventDate = Date()
        } else if !value {
          draft.eventDate = nil
        }
      }
    }
    .frame(minWidth: 360, minHeight: 500)
  }

  private func save() {
    do {
      try model.createWishlist(from: draft)
      dismiss()
    } catch let issue as ValidationIssue {
      validationMessage = issue.message
    } catch {
      validationMessage = "The wishlist could not be created."
    }
  }
}
