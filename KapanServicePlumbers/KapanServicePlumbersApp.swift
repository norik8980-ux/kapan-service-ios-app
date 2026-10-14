import SwiftUI

@main
struct KapanServicePlumbersApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var location = LocationPublisher()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(location)
        }
    }
}
