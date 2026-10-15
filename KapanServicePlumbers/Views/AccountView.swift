import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher

    @State private var confirmSignOut = false
    @State private var showAPISettings = false
    @State private var showDeveloper = false
    @State private var apiOverrideDraft = ""
    @State private var apiError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                KapanTheme.canvasGradient

                ScrollView {
                    VStack(spacing: 24) {
                        identityCard
                            .padding(.top, 8)

                        if let locationNote {
                            Text(locationNote)
                                .font(.caption)
                                .foregroundStyle(KapanTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        if showDeveloper || AppConfig.isUsingOverride {
                            developerCard
                        }

                        signOutButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .tint(KapanTheme.orange)
            .confirmationDialog(
                "Sign out?",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    location.stop()
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll need to sign in again.")
            }
            .sheet(isPresented: $showAPISettings) {
                APIBaseURLSheet(
                    draft: $apiOverrideDraft,
                    onCancel: { showAPISettings = false },
                    onSave: { await saveAPIOverride() }
                )
            }
            .onChange(of: location.sessionExpired) { _, expired in
                if expired {
                    Task { await session.signOut() }
                }
            }
        }
    }

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.user?.displayName ?? "Account")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(KapanTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.2) {
                    withAnimation { showDeveloper = true }
                }
                .accessibilityHint("Long-press for developer options")

            if let email = session.user?.email {
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(KapanTheme.muted)
            }

            if let user = session.user, user.isAdmin {
                Text(user.roleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KapanTheme.blue)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KapanTheme.border, lineWidth: 1)
        )
        .shadow(color: KapanTheme.ink.opacity(0.06), radius: 12, y: 4)
    }

    /// Quiet status only when location is actively relevant (sharing or blocked).
    private var locationNote: String? {
        if location.isSharing {
            return "Sharing location for the active job."
        }
        if session.user?.isPlumber == true, location.permissionDenied {
            return "Location is off — enable it in Settings for En route jobs."
        }
        return nil
    }

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Developer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)

            LabeledContent("Host", value: AppConfig.displayHost)
                .font(.subheadline)

            if AppConfig.isUsingOverride {
                Text("Custom base URL — not production.")
                    .font(.caption)
                    .foregroundStyle(KapanTheme.orangeDeep)
            }

            Button("Change API base URL…") {
                apiOverrideDraft = AppConfig.overrideString
                    ?? AppConfig.productionBaseURL.absoluteString
                apiError = nil
                showAPISettings = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KapanTheme.orange)

            if AppConfig.isUsingOverride {
                Button("Reset to production") {
                    Task {
                        location.stop()
                        await session.resetAPIBaseURLToProduction()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(KapanTheme.muted)
            }

            if let apiError {
                Text(apiError)
                    .font(.caption)
                    .foregroundStyle(KapanTheme.destructive)
            }

            Text("Changing the host signs you out.")
                .font(.caption2)
                .foregroundStyle(KapanTheme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KapanTheme.border, lineWidth: 1)
        )
    }

    private var signOutButton: some View {
        Button {
            confirmSignOut = true
        } label: {
            Text("Sign out")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(KapanTheme.destructive)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(KapanTheme.destructive.opacity(0.35), lineWidth: 1.5)
        )
    }

    private func saveAPIOverride() async {
        let raw = apiOverrideDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = {
            if raw.isEmpty { return nil }
            if raw == AppConfig.productionBaseURL.absoluteString
                || raw == AppConfig.productionBaseURL.host {
                return nil
            }
            return raw
        }()
        location.stop()
        let ok = await session.applyAPIBaseURLOverride(value)
        if ok {
            apiError = nil
            showAPISettings = false
            showDeveloper = true
        } else {
            apiError = "Enter a valid http(s) URL with a host."
            showAPISettings = false
            showDeveloper = true
        }
    }
}
