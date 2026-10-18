import SwiftUI
import UIKit
import UserNotifications

struct AccountView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var location: LocationPublisher
    @EnvironmentObject private var appLock: AppLockStore
    @ObservedObject private var push = PushRegistration.shared

    @State private var confirmSignOut = false
    @State private var showAPISettings = false
    @State private var showDeveloper = false
    @State private var apiOverrideDraft = ""
    @State private var apiError: String?

    @State private var supportPhone = MobileConfig.fallbackSupportPhone
    @State private var notificationAuth: UNAuthorizationStatus = .notDetermined
    @State private var pushBusy = false

    private var appVersionLabel: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(marketing) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KapanTheme.canvasGradient

                ScrollView {
                    VStack(spacing: 20) {
                        profileSection
                        supportSection
                        notificationsSection
                        permissionsSection
                        securitySection
                        aboutSection

                        if showDeveloper || AppConfig.isUsingOverride {
                            developerCard
                        }

                        signOutButton
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .tint(KapanTheme.orange)
            .confirmationDialog(
                "Sign out?",
                isPresented: $confirmSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    location.stop()
                    Task { await session.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll need to sign in again.")
            }
            .sheet(isPresented: $showAPISettings) {
                APIBaseURLSheet(
                    draft: $apiOverrideDraft,
                    onCancel: { showAPISettings = false },
                    onSave: { await saveAPIOverride() }
                )
            }
            .task {
                await refreshSupportPhone()
                await refreshNotificationStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await refreshNotificationStatus() }
            }
            .onChange(of: location.sessionExpired) { _, expired in
                if expired {
                    Task { await session.signOut() }
                }
            }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        accountPanel {
            Text(session.user?.displayName ?? "Account")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(KapanTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.2) {
                    withAnimation { showDeveloper = true }
                }
                .accessibilityHint("Long-press for developer options")

            if let email = session.user?.email {
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(KapanTheme.muted)
            }

            if let user = session.user, user.isAdmin {
                Text(user.roleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KapanTheme.blue)
            }
        }
    }

    private var supportSection: some View {
        accountPanel {
            sectionHeader("Support", support: "Call the office if you need dispatch.")

            if let telURL = MobileConfig.telURL(for: supportPhone) {
                Link(destination: telURL) {
                    HStack {
                        Text("Call dispatcher")
                            .foregroundStyle(KapanTheme.ink)
                        Spacer()
                        Text(supportPhone)
                            .foregroundStyle(KapanTheme.muted)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KapanTheme.muted)
                    }
                }
                .accessibilityLabel("Call dispatcher, \(supportPhone)")
            } else {
                HStack {
                    Text("Call dispatcher")
                    Spacer()
                    Text(supportPhone)
                        .foregroundStyle(KapanTheme.muted)
                }
            }
        }
    }

    private var notificationsSection: some View {
        accountPanel {
            sectionHeader("Notifications", support: "Get alerts when a job is assigned to you.")

            Toggle(isOn: Binding(
                get: { push.userWantsPush },
                set: { newValue in
                    Task { await setPushEnabled(newValue) }
                }
            )) {
                Text("Push notifications")
            }
            .tint(KapanTheme.orange)
            .disabled(pushBusy)

            Text(notificationStatusCopy)
                .font(.caption)
                .foregroundStyle(KapanTheme.muted)

            if notificationAuth == .denied {
                Button("Open Settings") { openSettings() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KapanTheme.orange)
            }
        }
    }

    private var permissionsSection: some View {
        accountPanel {
            sectionHeader("Permissions", support: "Required for field jobs and alerts.")

            Button { openSettings() } label: {
                permissionRow(
                    title: "Location",
                    value: locationOn ? "On" : "Off",
                    subtitle: locationSubtitle
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(KapanTheme.border)

            Button { openSettings() } label: {
                permissionRow(
                    title: "Notifications",
                    value: notificationsOn ? "On" : "Off",
                    subtitle: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var securitySection: some View {
        accountPanel {
            sectionHeader("Security", support: "Protect this device.")

            NavigationLink {
                ChangePasswordView()
            } label: {
                HStack {
                    Text("Change password")
                        .foregroundStyle(KapanTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KapanTheme.muted)
                }
            }

            Divider().overlay(KapanTheme.border)

            Toggle(isOn: Binding(
                get: { appLock.isEnabled },
                set: { appLock.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock with Face ID")
                    Text("Require Face ID when opening the app on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(KapanTheme.muted)
                }
            }
            .tint(KapanTheme.orange)

            if let msg = appLock.unavailableMessage, !appLock.biometryAvailable {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(KapanTheme.muted)
            }
        }
    }

    private var aboutSection: some View {
        accountPanel {
            sectionHeader("About", support: nil)
            HStack {
                Text("Version")
                Spacer()
                Text(appVersionLabel)
                    .foregroundStyle(KapanTheme.muted)
            }
            .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, support: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
                .textCase(.uppercase)
            if let support {
                Text(support)
                    .font(.caption)
                    .foregroundStyle(KapanTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private func accountPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KapanTheme.border, lineWidth: 1)
        )
        .shadow(color: KapanTheme.ink.opacity(0.06), radius: 12, y: 4)
    }

    private func permissionRow(title: String, value: String, subtitle: String?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(KapanTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(KapanTheme.muted)
                }
            }
            Spacer()
            Text(value)
                .foregroundStyle(KapanTheme.muted)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)
        }
        .font(.subheadline)
    }

    private var locationOn: Bool {
        location.authorization == .authorizedWhenInUse
            || location.authorization == .authorizedAlways
    }

    private var notificationsOn: Bool {
        switch notificationAuth {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private var locationSubtitle: String? {
        if location.isSharing {
            return "Sharing for the active job."
        }
        if !locationOn {
            return "Enable in Settings for En route jobs."
        }
        return nil
    }

    private var notificationStatusCopy: String {
        switch notificationAuth {
        case .authorized:
            return "Status: Allowed"
        case .denied:
            return "Status: Off in iPhone Settings"
        case .notDetermined:
            return "Status: Not set yet"
        case .provisional, .ephemeral:
            return "Status: Limited"
        @unknown default:
            return "Status: Limited"
        }
    }

    private func setPushEnabled(_ on: Bool) async {
        pushBusy = true
        defer { pushBusy = false }
        if on {
            await push.enablePushFromAccount()
        } else {
            await push.disablePushFromAccount()
        }
        await refreshNotificationStatus()
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuth = settings.authorizationStatus
    }

    private func refreshSupportPhone() async {
        do {
            let config = try await APIClient.shared.mobileConfig()
            let phone = config.supportPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            if !phone.isEmpty {
                supportPhone = phone
            }
        } catch {
            // Keep NAP fallback.
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Developer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KapanTheme.muted)

            LabeledContent("Host", value: AppConfig.displayHost)
                .font(.subheadline)

            if AppConfig.isUsingOverride {
                Text("Custom base URL — not production.")
                    .font(.caption)
                    .foregroundStyle(KapanTheme.orangeDeep)
            }

            Button("Change API base URL…") {
                apiOverrideDraft = AppConfig.overrideString
                    ?? AppConfig.productionBaseURL.absoluteString
                apiError = nil
                showAPISettings = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KapanTheme.orange)

            if AppConfig.isUsingOverride {
                Button("Reset to production") {
                    Task {
                        location.stop()
                        await session.resetAPIBaseURLToProduction()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(KapanTheme.muted)
            }

            if let apiError {
                Text(apiError)
                    .font(.caption)
                    .foregroundStyle(KapanTheme.destructive)
            }

            Text("Changing the host signs you out.")
                .font(.caption2)
                .foregroundStyle(KapanTheme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KapanTheme.border, lineWidth: 1)
        )
    }

    private var signOutButton: some View {
        Button {
            confirmSignOut = true
        } label: {
            Text("Sign out")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(KapanTheme.destructive)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(KapanTheme.destructive.opacity(0.35), lineWidth: 1.5)
        )
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
        location.stop()
        let ok = await session.applyAPIBaseURLOverride(value)
        if ok {
            apiError = nil
            showAPISettings = false
            showDeveloper = true
        } else {
            apiError = "Enter a valid http(s) URL with a host."
            showAPISettings = false
            showDeveloper = true
        }
    }
}
