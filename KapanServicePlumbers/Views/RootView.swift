import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher
    @EnvironmentObject private var appLock: AppLockStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var locationGatePassed = false

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
                ZStack {
                    MainTabView()
                    if appLock.isLocked {
                        AppUnlockOverlay()
                    }
                }
            } else if locationGatePassed || locationAuthorized {
                LoginView()
            } else {
                LocationConsentView {
                    locationGatePassed = true
                }
            }
        }
        .tint(KapanTheme.orange)
        .animation(.easeInOut(duration: 0.2), value: session.isSignedIn)
        .animation(.easeInOut(duration: 0.2), value: session.bootstrapped)
        .animation(.easeInOut(duration: 0.2), value: locationGatePassed)
        .onAppear {
            if locationAuthorized {
                locationGatePassed = true
            }
        }
        .onChange(of: location.authorization) { _, _ in
            if locationAuthorized {
                locationGatePassed = true
            }
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                location.stop()
                appLock.setSignedIn(false)
                // Returning to login still requires location if revoked.
                locationGatePassed = locationAuthorized
            } else {
                appLock.setSignedIn(true)
            }
        }
        .onChange(of: session.bootstrapped) { _, ready in
            guard ready, session.isSignedIn else { return }
            appLock.setSignedIn(true)
            appLock.lockIfNeededForColdStart()
        }
        .onChange(of: scenePhase) { _, phase in
            appLock.handleScenePhase(phase)
        }
        .onChange(of: location.sessionExpired) { _, expired in
            if expired {
                Task { await session.signOut() }
            }
        }
    }

    private var locationAuthorized: Bool {
        location.authorization == .authorizedWhenInUse
            || location.authorization == .authorizedAlways
    }
}

/// Full-screen Face ID lock while signed in (scope A).
private struct AppUnlockOverlay: View {
    @EnvironmentObject private var appLock: AppLockStore

    var body: some View {
        ZStack {
            KapanTheme.canvasGradient
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(KapanTheme.orange)
                Text(KapanTheme.brandName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KapanTheme.ink)
                Text("Unlock with Face ID")
                    .font(.subheadline)
                    .foregroundStyle(KapanTheme.muted)
                if let err = appLock.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(KapanTheme.destructive)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button {
                    Task { await appLock.unlock() }
                } label: {
                    Text("Unlock")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(KapanTheme.orange)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
        .task {
            await appLock.unlock()
        }
    }
}
