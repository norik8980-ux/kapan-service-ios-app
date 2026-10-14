import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section("Signed in") {
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.roleLabel)
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
                        Text("Location is only shared while a job is En route.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Kapan Service Plumbers")
                    LabeledContent("API", value: "kapanservice.com")
                    Text("Approach SMS fires once within 3 miles while En route. Chat messages send as outbound SMS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        location.stop()
                        Task { await session.signOut() }
                    }
                }
            }
            .navigationTitle("Account")
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
}
