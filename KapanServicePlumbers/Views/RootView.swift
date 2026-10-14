import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Group {
            if !session.bootstrapped {
                ProgressView("Loading…")
            } else if session.isSignedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}
