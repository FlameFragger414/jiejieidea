import SwiftUI

@main
struct JiejieIOSApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      IOSRootView()
        .environmentObject(model)
    }
  }
}
