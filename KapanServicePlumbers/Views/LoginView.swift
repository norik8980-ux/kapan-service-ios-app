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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kapan Service Plumbers")
                            .font(.largeTitle.bold())
                        Text("Sign in as office dispatch or plumber. Jobs, assign, chat → SMS, and approach alerts at 3 miles.")
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 4)
                }

                Section("Sign in") {
                    TextField("Email", text: $login)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
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
                        HStack {
                            Spacer()
                            if busy {
                                ProgressView()
                            } else {
                                Text("Sign in").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(busy || login.isEmpty || password.isEmpty)
                } footer: {
                    Text("Uses kapanservice.com mobile API. Admin and plumber accounts only.")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.signIn(
                login: login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                password: password
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
