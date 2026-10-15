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
            List {
                if let user = session.user {
                    Section {
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Email", value: user.email)
                        HStack {
                            Text("Role")
                            Spacer()
                            RoleBadge(role: user.role)
                        }
                    } header: {
                        Text("Signed in")
                    }
                }

                Section("Location") {
                    LabeledContent("Permission", value: locationPermissionLabel)
                    if location.isSharing, let id = location.activeBookingId {
                        LabeledContent("Sharing for job", value: String(id.prefix(8)) + "…")
                        Button("Stop sharing", role: .destructive) {
                            location.stop()
                        }
                    } else if session.user?.isPlumber == true {
                        Text("Shared only while a job is En route.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if showDeveloper || AppConfig.isUsingOverride {
                    Section {
                        LabeledContent("Host", value: AppConfig.displayHost)
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
                        if AppConfig.isUsingOverride {
                            Button("Reset to production") {
                                Task {
                                    location.stop()
                                    await session.resetAPIBaseURLToProduction()
                                }
                            }
                        }
                        if let apiError {
                            Text(apiError).font(.caption).foregroundStyle(KapanTheme.destructive)
                        }
                    } header: {
                        Text("Developer")
                    } footer: {
                        Text("Changing the host signs you out.")
                    }
                }

                Section("About") {
                    Text(KapanTheme.brandName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(KapanTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 1.2) {
                            withAnimation { showDeveloper = true }
                        }
                        .accessibilityHint("Long-press for developer options")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        confirmSignOut = true
                    }
                }
            }
            .navigationTitle("Account")
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

    private var locationPermissionLabel: String {
        switch location.authorization {
        case .notDetermined: return "Not asked yet"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While using"
        @unknown default: return "Unknown"
        }
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
