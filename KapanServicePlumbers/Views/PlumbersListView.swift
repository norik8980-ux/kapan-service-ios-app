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
                        Text("Share securely, then have them change it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Team (\(plumbers.count))") {
                    if !loading && plumbers.isEmpty && error == nil && hasLoadedOnce {
                        ContentUnavailableView {
                            Label("No plumbers yet", systemImage: "person.2")
                        } description: {
                            Text("Tap + to add the first plumber.")
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
                                    .foregroundStyle(
                                        p.active
                                            ? Color(red: 0.18, green: 0.64, blue: 0.36)
                                            : KapanTheme.muted
                                    )
                            }
                            Text(p.email)
                                .font(.caption)
                                .foregroundStyle(KapanTheme.muted)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Plumbers")
            .tint(KapanTheme.orange)
            .toolbar {
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
                        Text(addError).foregroundStyle(KapanTheme.destructive)
                    }
                }
            }
            .navigationTitle("Add plumber")
            .navigationBarTitleDisplayMode(.inline)
            .tint(KapanTheme.orange)
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
                if adding { ProgressView().tint(KapanTheme.orange) }
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
            if APIError.isCancellation(error) || Task.isCancelled { return }
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
