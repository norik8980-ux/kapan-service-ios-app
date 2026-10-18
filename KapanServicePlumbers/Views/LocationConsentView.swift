import CoreLocation
import SwiftUI
import UIKit

/// Hard gate before Login: When-In-Use location must be allowed to sign in.
struct LocationConsentView: View {
    @EnvironmentObject private var location: LocationPublisher
    var onAuthorized: () -> Void

    var body: some View {
        ZStack {
            KapanTheme.canvasGradient

            VStack(spacing: 28) {
                brandMark
                    .padding(.top, 48)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(KapanTheme.ink)
                        .multilineTextAlignment(.center)

                    Text(bodyCopy)
                        .font(.subheadline)
                        .foregroundStyle(KapanTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)

                VStack(spacing: 12) {
                    if location.permissionDenied {
                        Button {
                            openSettings()
                        } label: {
                            Text("Open Settings")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(KapanTheme.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        Button {
                            location.requestPermissionIfNeeded()
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(KapanTheme.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(20)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(KapanTheme.border, lineWidth: 1)
                )
                .shadow(color: KapanTheme.ink.opacity(0.06), radius: 12, y: 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onAppear { advanceIfAuthorized() }
        .onChange(of: location.authorization) { _, _ in
            advanceIfAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            advanceIfAuthorized()
        }
    }

    private var brandMark: some View {
        VStack(spacing: 14) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [KapanTheme.orange, KapanTheme.orangeDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: KapanTheme.orange.opacity(0.35), radius: 10, y: 4)
                .accessibilityLabel(KapanTheme.brandName)

            Text(KapanTheme.brandName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(KapanTheme.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        location.permissionDenied ? "Location is off" : "Location required"
    }

    private var bodyCopy: String {
        if location.permissionDenied {
            return "Turn on Location for Kapan Service Plumbers in Settings, then return here to sign in."
        }
        return "We use your location during active jobs so customers get an approaching SMS (about 3 miles). You can’t sign in until location access is allowed."
    }

    private func advanceIfAuthorized() {
        switch location.authorization {
        case .authorizedWhenInUse, .authorizedAlways:
            onAuthorized()
        default:
            break
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
