import SwiftUI

struct PlumbersListView: View {
    @State private var plumbers: [PlumberAccount] = []
    @State private var error: String?
    @State private var showAdd = false
    @State private var newEmail = ""
    @State private var newName = ""
    @State private var tempPassword: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                if let tempPassword {
                    Section("Temporary password") {
                        Text(tempPassword)
                            .font(.body.monospaced())
                        Text("Share securely with the plumber, then change it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(plumbers) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.displayName).font(.headline)
                        Text(p.email).font(.caption).foregroundStyle(.secondary)
                        Text(p.active ? "Active" : "Inactive")
                            .font(.caption2)
                            .foregroundStyle(p.active ? .green : .secondary)
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
                        TextField("Email", text: $newEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        TextField("Name", text: $newName)
                    }
                    .navigationTitle("Add plumber")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showAdd = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                Task { await add() }
                            }
                            .disabled(newEmail.isEmpty)
                        }
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
        }
    }

    private func add() async {
        do {
            let result = try await APIClient.shared.createPlumber(
                email: newEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                name: newName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            tempPassword = result.temporaryPassword
            showAdd = false
            newEmail = ""
            newName = ""
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
