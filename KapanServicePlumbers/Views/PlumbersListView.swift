import SwiftUI
import UIKit

struct PlumbersListView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var plumbers: [PlumberAccount] = []
    @State private var error: String?
    @State private var loading = false
    @State private var hasLoadedOnce = false
    @State private var showAdd = false
    @State private var newEmail = ""
    @State private var newName = ""
    @State private var adding = false
    @State private var addError: String?
    @State private var tempPassword: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Admin only — manage field plumbers. Start with 2; add more anytime. Temporary passwords are shown once after create.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        InlineErrorRow(message: error) {
                            Task { await load() }
                        }
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
                    if !loading && plumbers.isEmpty && error == nil && hasLoadedOnce {
                        ContentUnavailableView {
                            Label("No plumbers yet", systemImage: "person.2")
                        } description: {
                            Text("Tap + to add the first plumber account.")
                        }
                        .listRowBackground(Color.clear)
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
                ToolbarItem(placement: .topBarLeading) {
                    RoleBadge(role: "admin")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addError = nil
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add plumber")
                }
            }
            .sheet(isPresented: $showAdd) {
                addPlumberSheet
            }
            .task { await load() }
            .refreshable { await load() }
            .overlay {
                if loading && plumbers.isEmpty {
                    LoadingStateView(message: "Loading plumbers…")
                }
            }
        }
    }

    private var addPlumberSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $newEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .disabled(adding)
                    TextField("Name", text: $newName)
                        .textContentType(.name)
                        .disabled(adding)
                } footer: {
                    Text("A temporary password is generated automatically.")
                }
                if let addError {
                    Section {
                        Text(addError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add plumber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAdd = false }
                        .disabled(adding)
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
            .interactiveDismissDisabled(adding)
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer {
            loading = false
            hasLoadedOnce = true
        }
        do {
            plumbers = try await APIClient.shared.plumbers()
        } catch {
            self.error = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }

    private func add() async {
        guard !adding else { return }
        adding = true
        addError = nil
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
            addError = error.localizedDescription
            await session.handleUnauthorized(error)
        }
    }
}
