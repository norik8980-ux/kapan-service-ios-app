import SwiftUI

@main
struct KapanServicePlumbersApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionStore()
    @StateObject private var location = LocationPublisher()
    @StateObject private var pushRouter = PushRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(location)
                .environmentObject(pushRouter)
        }
    }
}
