import SwiftUI

/// Centered loading indicator for first-load screens.
struct LoadingStateView: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(KapanTheme.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(KapanTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Error block with optional Retry — use in lists or as a full-screen stand-in.
struct ErrorStateView: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle"
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(KapanTheme.orange)
            }
        }
    }
}

/// Compact inline error row for Forms / Lists.
struct InlineErrorRow: View {
    let message: String
    var centered: Bool = false
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(message)
                .foregroundStyle(KapanTheme.destructive)
                .font(.subheadline)
                .multilineTextAlignment(centered ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            if let onRetry {
                Button("Try again", action: onRetry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KapanTheme.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.vertical, 2)
    }
}

/// Role chip for Admin vs Plumber.
struct RoleBadge: View {
    let role: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private var label: String {
        switch role {
        case "admin": return "Admin"
        case "plumber": return "Plumber"
        default: return role.capitalized
        }
    }

    private var tint: Color {
        switch role {
        case "admin": return KapanTheme.blue
        case "plumber": return KapanTheme.orangeDeep
        default: return KapanTheme.muted
        }
    }
}

/// Shared sheet to override API base URL (hidden from normal users).
struct APIBaseURLSheet: View {
    @Binding var draft: String
    var onCancel: () -> Void
    var onSave: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Base URL", text: $draft)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                } footer: {
                    Text("Examples: https://kapanservice.com or \(AppConfig.localDefaultURLString)")
                }
                Section {
                    Button("Use production") {
                        draft = AppConfig.productionBaseURL.absoluteString
                    }
                    Button("Use local default") {
                        draft = AppConfig.localDefaultURLString
                    }
                }
            }
            .navigationTitle("API base URL")
            .navigationBarTitleDisplayMode(.inline)
            .tint(KapanTheme.orange)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await onSave() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
