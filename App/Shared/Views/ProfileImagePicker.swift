import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
  import PhotosUI
#endif

/// Picks a profile image using the control that belongs on each platform: the photo library on
/// iOS and the standard open panel on macOS.
struct ProfileImagePicker: View {
  let hasExistingImage: Bool
  let isBusy: Bool
  let onImagePicked: (Data) -> Void
  let onRemove: () -> Void

  @State private var isImporting = false
  @State private var importFailure: String?

  #if os(iOS)
    @State private var selection: PhotosPickerItem?
  #endif

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        #if os(iOS)
          PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Label(buttonTitle, systemImage: "photo.on.rectangle")
          }
          .buttonStyle(.bordered)
          .disabled(isBusy)
          .accessibilityHint("Opens your photo library")
          .onChange(of: selection) { item in
            guard let item else { return }
            Task { await load(item) }
          }
        #else
          Button {
            isImporting = true
          } label: {
            Label(buttonTitle, systemImage: "photo.on.rectangle")
          }
          .buttonStyle(.bordered)
          .disabled(isBusy)
          .accessibilityHint("Opens a file chooser")
        #endif

        if hasExistingImage {
          Button(role: .destructive) {
            onRemove()
          } label: {
            Label("Remove photo", systemImage: "trash")
          }
          .buttonStyle(.bordered)
          .disabled(isBusy)
        }
      }

      Text("Optional. JPEG, PNG, HEIC, or WebP, resized on this device before upload.")
        .font(.footnote)
        .foregroundStyle(.secondary)

      if let importFailure {
        FailureNotice(message: importFailure)
      }
    }
    .fileImporter(
      isPresented: $isImporting,
      allowedContentTypes: [.jpeg, .png, .heic, .webP],
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
  }

  private var buttonTitle: String {
    hasExistingImage ? "Replace photo" : "Add a photo"
  }

  #if os(iOS)
    private func load(_ item: PhotosPickerItem) async {
      importFailure = nil
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          importFailure = "That photo could not be read. Choose another one."
          return
        }
        onImagePicked(data)
      } catch {
        importFailure = "That photo could not be read. Choose another one."
      }
      selection = nil
    }
  #endif

  private func handleImport(_ result: Result<[URL], any Error>) {
    importFailure = nil
    guard case .success(let urls) = result, let url = urls.first else {
      if case .failure = result {
        importFailure = "That image could not be opened. Choose another one."
      }
      return
    }

    // Files chosen through the open panel are outside the app sandbox until access is requested.
    let needsScopedAccess = url.startAccessingSecurityScopedResource()
    defer {
      if needsScopedAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    guard let data = try? Data(contentsOf: url) else {
      importFailure = "That image could not be opened. Choose another one."
      return
    }
    onImagePicked(data)
  }
}
