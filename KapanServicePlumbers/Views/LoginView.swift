import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var login = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showAPISettings = false
    @State private var apiOverrideDraft = AppConfig.overrideString ?? ""

    private static let emailMaxLength = 100
    private static let passwordMaxLength = 100

    var body: some View {
        NavigationStack {
            ZStack {
                KapanTheme.canvasGradient

                ScrollView {
                    VStack(spacing: 28) {
                        brandHeader
                            .padding(.top, 48)

                        VStack(spacing: 16) {
                            fieldBlock

                            if let error {
                                InlineErrorRow(message: error)
                                    .padding(.horizontal, 4)
                            }

                            Button {
                                Task { await submit() }
                            } label: {
                                HStack {
                                    Spacer()
                                    if busy {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("Sign in")
                                            .font(.headline)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                            .background(
                                canSubmit && !busy
                                    ? KapanTheme.orange
                                    : KapanTheme.orange.opacity(0.45)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .disabled(busy || !canSubmit)
                        }
                        .padding(20)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(KapanTheme.border, lineWidth: 1)
                        )
                        .shadow(color: KapanTheme.ink.opacity(0.06), radius: 12, y: 4)

                        if AppConfig.isUsingOverride {
                            Text("Custom API host: \(AppConfig.displayHost)")
                                .font(.caption2)
                                .foregroundStyle(KapanTheme.orangeDeep)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(busy)
            .sheet(isPresented: $showAPISettings) {
                APIBaseURLSheet(
                    draft: $apiOverrideDraft,
                    onCancel: { showAPISettings = false },
                    onSave: { await saveAPIOverride() }
                )
            }
        }
        .tint(KapanTheme.orange)
    }

    private var brandHeader: some View {
        VStack(spacing: 14) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [KapanTheme.orange, KapanTheme.orangeDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: KapanTheme.orange.opacity(0.35), radius: 10, y: 4)
                .accessibilityLabel(KapanTheme.brandName)
                .onLongPressGesture(minimumDuration: 1.2) {
                    apiOverrideDraft = AppConfig.overrideString
                        ?? AppConfig.productionBaseURL.absoluteString
                    showAPISettings = true
                }

            Text(KapanTheme.brandName)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(KapanTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text(KapanTheme.brandTagline)
                .font(.subheadline)
                .foregroundStyle(KapanTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var fieldBlock: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $login)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .autocorrectionDisabled()
                .padding(14)
                .background(KapanTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(KapanTheme.border, lineWidth: 1)
                )
                .disabled(busy)
                .onChange(of: login) { _, newValue in
                    if newValue.count > Self.emailMaxLength {
                        login = String(newValue.prefix(Self.emailMaxLength))
                    }
                }

            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(14)
                .background(KapanTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(KapanTheme.border, lineWidth: 1)
                )
                .disabled(busy)
                .onChange(of: password) { _, newValue in
                    if newValue.count > Self.passwordMaxLength {
                        password = String(newValue.prefix(Self.passwordMaxLength))
                    }
                }
        }
    }

    private var canSubmit: Bool {
        !login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
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
