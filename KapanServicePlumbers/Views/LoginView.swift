import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var login = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showAPISettings = false
    @State private var apiOverrideDraft = AppConfig.overrideString ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kapan Service Plumbers")
                            .font(.largeTitle.bold())
                        Text("Office dispatch and field plumbers — jobs, assign, chat → SMS, approach alert at 3 miles.")
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
                        .disabled(busy)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .disabled(busy)
                }

                if let error {
                    Section {
                        InlineErrorRow(message: error) {
                            Task { await submit() }
                        }
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
                    .disabled(busy || !canSubmit)
                } footer: {
                    Text("Admin sees all jobs and can assign plumbers. Plumbers see only their assigned jobs.")
                }

                Section {
                    LabeledContent("Host", value: AppConfig.displayHost)
                    if AppConfig.isUsingOverride {
                        Text("Using a custom base URL (not production).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Change API base URL…") {
                        apiOverrideDraft = AppConfig.overrideString ?? AppConfig.productionBaseURL.absoluteString
                        showAPISettings = true
                    }
                    .disabled(busy)
                } header: {
                    Text("API server")
                } footer: {
                    Text("Default is \(AppConfig.productionBaseURL.absoluteString). Use local (e.g. \(AppConfig.localDefaultURLString)) only for development.")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(busy)
            .sheet(isPresented: $showAPISettings) {
                apiSettingsSheet
            }
        }
    }

    private var canSubmit: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
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
        let ok = await session.applyAPIBaseURLOverride(value)
        if ok {
            showAPISettings = false
            error = nil
        } else {
            error = "Enter a valid http(s) URL with a host."
            showAPISettings = false
        }
    }

    private func submit() async {
        guard canSubmit, !busy else { return }
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
