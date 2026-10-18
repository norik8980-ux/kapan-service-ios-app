import SwiftUI

struct ChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var error: String?
    @State private var successMessage: String?

    private static let minLength = 10

    var body: some View {
        ZStack {
            KapanTheme.canvasGradient

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Current password", text: $currentPassword)
                    field("New password", text: $newPassword)
                    field("Confirm new password", text: $confirmPassword)

                    if let error {
                        InlineErrorRow(message: error)
                    }
                    if let successMessage {
                        Text(successMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.18, green: 0.64, blue: 0.36))
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy {
                                ProgressView().tint(.white)
                            } else {
                                Text("Update password")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(canSubmit && !busy ? KapanTheme.orange : KapanTheme.orange.opacity(0.45))
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
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
        .tint(KapanTheme.orange)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
            SecureField(title, text: text)
                .textContentType(.password)
                .padding(14)
                .background(KapanTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(KapanTheme.border, lineWidth: 1)
                )
                .disabled(busy)
        }
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && !confirmPassword.isEmpty
    }

    private func submit() async {
        guard canSubmit, !busy else { return }
        busy = true
        error = nil
        successMessage = nil
        defer { busy = false }

        if let local = validateLocal() {
            error = local
            return
        }

        do {
            try await APIClient.shared.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            successMessage = "Password updated."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Mirror web `password-policy` (length / letter+digit / no spaces / match).
    private func validateLocal() -> String? {
        if newPassword != confirmPassword {
            return "New passwords don’t match."
        }
        if newPassword.count < Self.minLength {
            return "New password must be at least \(Self.minLength) characters"
        }
        if newPassword.rangeOfCharacter(from: .letters) == nil
            || newPassword.rangeOfCharacter(from: .decimalDigits) == nil {
            return "New password must include at least one letter and one number"
        }
        if newPassword.contains(where: { $0.isWhitespace }) {
            return "New password cannot contain spaces"
        }
        if newPassword == currentPassword {
            return "New password must be different from your current password"
        }
        return nil
    }
}
