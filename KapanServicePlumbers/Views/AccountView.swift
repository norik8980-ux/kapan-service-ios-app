import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher

    @State private var confirmSignOut = false
    @State private var showAPISettings = false
    @State private var apiOverrideDraft = ""
    @State private var apiError: String?

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section("Signed in") {
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Email", value: user.email)
                        HStack {
                            Text("Role")
                            Spacer()
                            RoleBadge(role: user.role)
                        }
                        Text(roleBlurb(for: user))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    LabeledContent(
                        "Permission",
                        value: locationPermissionLabel
                    )
                    if location.isSharing, let id = location.activeBookingId {
                        LabeledContent("Sharing for job", value: String(id.prefix(8)) + "…")
                        Button("Stop sharing", role: .destructive) {
                            location.stop()
                        }
                    } else {
                        Text(
                            session.user?.isPlumber == true
                                ? "Location is only shared while a job is En route."
                                : "Admins do not share GPS. Plumbers share only while En route."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("API server") {
                    LabeledContent("Host", value: AppConfig.displayHost)
                    if AppConfig.isUsingOverride {
                        Text("Custom base URL — not production.")
                            .font(.caption)
                            .foregroundStyle(.orange)
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
                        Text(apiError).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Changing the API host signs you out. Default: \(AppConfig.productionBaseURL.absoluteString)")
                }

                Section("About") {
                    LabeledContent("App", value: "Kapan Service Plumbers")
                    Text("Approach SMS fires once within 3 miles while En route. Chat messages send as outbound SMS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        confirmSignOut = true
                    }
                }
            }
            .navigationTitle("Account")
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
                Text("Location sharing stops and you’ll need to sign in again.")
            }
            .sheet(isPresented: $showAPISettings) {
                apiSettingsSheet
            }
            .onChange(of: location.sessionExpired) { _, expired in
                if expired {
                    Task { await session.signOut() }
                }
            }
        }
    }

    private func roleBlurb(for user: MobileUser) -> String {
        if user.isAdmin {
            return "Admin / Dispatch: see all jobs, assign plumbers, chat as the office."
        }
        if user.isPlumber {
            return "Plumber: your assigned jobs, field status, GPS while En route, customer SMS."
        }
        return "Limited access for this role."
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

    private var apiSettingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Base URL", text: $apiOverrideDraft)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                } footer: {
                    Text("Examples: https://kapanservice.com or \(AppConfig.localDefaultURLString)")
                }
                Section {
                    Button("Use production") {
                        apiOverrideDraft = AppConfig.productionBaseURL.absoluteString
                    }
                    Button("Use local default") {
                        apiOverrideDraft = AppConfig.localDefaultURLString
                    }
                }
            }
            .navigationTitle("API base URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAPISettings = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveAPIOverride() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
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
        } else {
            apiError = "Enter a valid http(s) URL with a host."
            showAPISettings = false
        }
    }
}
