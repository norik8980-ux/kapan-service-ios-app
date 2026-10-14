import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section("Signed in") {
                        LabeledContent("Name", value: user.displayName)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.role)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut() }
                    }
                }
                Section("About") {
                    Text("Kapan Service Plumbers")
                    Text("API: kapanservice.com")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Account")
        }
    }
}
