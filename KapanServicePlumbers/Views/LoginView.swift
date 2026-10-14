import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var login = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Kapan Service Plumbers")
                        .font(.largeTitle.bold())
                        .listRowBackground(Color.clear)
                    Text("Field app for dispatch and plumbers")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Sign in") {
                    TextField("Email", text: $login)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Text("Sign in")
                        }
                    }
                    .disabled(busy || login.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Welcome")
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.signIn(login: login.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
