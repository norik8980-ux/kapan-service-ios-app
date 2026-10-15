import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher

    var body: some View {
        Group {
            if !session.bootstrapped {
                ZStack {
                    KapanTheme.canvasGradient
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(KapanTheme.orange)
                        Text(KapanTheme.brandName)
                            .font(.headline)
                            .foregroundStyle(KapanTheme.ink)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            } else if session.isSignedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .tint(KapanTheme.orange)
        .animation(.easeInOut(duration: 0.2), value: session.isSignedIn)
        .animation(.easeInOut(duration: 0.2), value: session.bootstrapped)
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                location.stop()
            }
        }
        .onChange(of: location.sessionExpired) { _, expired in
            if expired {
                Task { await session.signOut() }
            }
        }
    }
}
