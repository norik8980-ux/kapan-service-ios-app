import SwiftUI

/// Centered loading indicator for first-load screens.
struct LoadingStateView: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            }
        }
    }
}

/// Compact inline error row for Forms / Lists.
struct InlineErrorRow: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .foregroundStyle(.red)
                .font(.subheadline)
            if let onRetry {
                Button("Try again", action: onRetry)
                    .font(.subheadline.weight(.semibold))
            }
        }
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
        case "admin": return "Admin / Dispatch"
        case "plumber": return "Plumber"
        default: return role.capitalized
        }
    }

    private var tint: Color {
        switch role {
        case "admin": return .blue
        case "plumber": return .teal
        default: return .secondary
        }
    }
}
