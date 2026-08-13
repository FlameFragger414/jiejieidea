import SwiftUI

@main
struct JiejieMacOSApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      MacRootView()
        .environmentObject(model)
        .frame(minWidth: 820, minHeight: 560)
    }
    .defaultSize(width: 1_080, height: 720)
    .commands {
      CommandMenu("Wishlist") {
        Button("New Wishlist") {
          NotificationCenter.default.post(name: .newWishlistRequested, object: nil)
        }
        .keyboardShortcut("n", modifiers: .command)
      }
    }
  }
}
