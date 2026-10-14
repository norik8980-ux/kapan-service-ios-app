import SwiftUI
import UIKit

struct PlumbersListView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var plumbers: [PlumberAccount] = []
    @State private var error: String?
    @State private var showAdd = false
    @State private var newEmail = ""
    @State private var newName = ""
    @State private var adding = false
    @State private var tempPassword: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Start with 2 plumbers; add more anytime. Temporary passwords are shown once after create.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if let tempPassword {
                    Section("Temporary password") {
                        Text(tempPassword)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = tempPassword
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy password", systemImage: "doc.on.doc")
                        }
                        Text("Share securely with the plumber, then have them change it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Team (\(plumbers.count))") {
                    if plumbers.isEmpty {
                        Text("No plumbers yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plumbers) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(p.displayName).font(.headline)
                                Spacer()
                                Text(p.active ? "Active" : "Inactive")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(p.active ? .green : .secondary)
                            }
                            Text(p.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Plumbers")
            .toolbar {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("Email", text: $newEmail)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                            TextField("Name", text: $newName)
                                .textContentType(.name)
                        } footer: {
                            Text("A temporary password is generated automatically.")
                        }
                        if let error {
                            Section { Text(error).foregroundStyle(.red) }
                        }
                    }
                    .navigationTitle("Add plumber")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                Task { await add() }
                            }
                            .disabled(adding || newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .overlay {
                        if adding { ProgressView() }
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            plumbers = try await APIClient.shared.plumbers()
            error = nil
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }

    private func add() async {
        adding = true
        defer { adding = false }
        do {
            let result = try await APIClient.shared.createPlumber(
                email: newEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                name: newName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            tempPassword = result.temporaryPassword
            copied = false
            showAdd = false
            newEmail = ""
            newName = ""
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }
}
