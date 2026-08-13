import SwiftUI

@main
struct JiejieIOSApp: App {
  @StateObject private var session = SessionController()
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      IOSRootView()
        .environmentObject(session)
        .environmentObject(model)
    }
  }
}
