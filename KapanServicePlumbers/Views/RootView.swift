import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher

    var body: some View {
        Group {
            if !session.bootstrapped {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Kapan Service Plumbers")
                        .font(.headline)
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
            } else if session.isSignedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                location.stop()
            }
        }
    }
}
