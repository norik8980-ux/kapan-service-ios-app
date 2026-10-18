import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: MobileUser?
    @Published var token: String?
    @Published var features: MobileFeatures = .disabled
    @Published var bootstrapped = false
    @Published var restoring = false

    private let tokenKey = "kapan.mobile.token"

    init() {
        Task { await restore() }
    }

    var isSignedIn: Bool { token != nil && user != nil }

    func restore() async {
        restoring = true
        defer {
            restoring = false
            bootstrapped = true
        }
        await APIClient.shared.applyConfiguredBaseURL()
        guard let saved = loadToken(), !saved.isEmpty else {
            return
        }
        token = saved
        await APIClient.shared.setToken(saved)
        do {
            let me = try await APIClient.shared.me()
            user = me.user
            features = me.features ?? .disabled
            PushRegistration.shared.setSignedIn(true)
        } catch {
            // Invalid / expired token — clear local session quietly.
            await clearSessionLocally()
        }
    }

    func signIn(login: String, password: String) async throws {
        await APIClient.shared.applyConfiguredBaseURL()
        let response = try await APIClient.shared.login(login: login, password: password)
        token = response.token
        user = response.user
        persistToken(response.token)
        await APIClient.shared.setToken(response.token)
        PushRegistration.shared.setSignedIn(true)
        await refreshFeatures()
    }

    /// Refresh feature flags from `/me` (compat; Open jobs tab is always on).
    func refreshFeatures() async {
        guard token != nil else {
            features = .disabled
            return
        }
        do {
            let me = try await APIClient.shared.me()
            user = me.user
            features = me.features ?? .disabled
        } catch {
            // Keep last known features on transient errors.
            if let api = error as? APIError, case .unauthorized = api {
                features = .disabled
            }
        }
    }

    /// Clears credentials and API token. Callers should stop location sharing first.
    func signOut() async {
        await PushRegistration.shared.unregisterOnSignOut()
        await clearSessionLocally()
    }

    /// Clear local session when API returns 401.
    func handleUnauthorized(_ error: Error) async {
        if let api = error as? APIError, case .unauthorized = api {
            await PushRegistration.shared.unregisterOnSignOut()
            await clearSessionLocally()
        }
    }

    private func clearSessionLocally() async {
        token = nil
        user = nil
        features = .disabled
        clearPersistedToken()
        await APIClient.shared.setToken(nil)
    }

    /// Apply a new API base URL override and drop the session (token is host-scoped).
    func applyAPIBaseURLOverride(_ raw: String?) async -> Bool {
        guard AppConfig.setOverride(raw) else { return false }
        await APIClient.shared.applyConfiguredBaseURL()
        await clearSessionLocally()
        return true
    }

    func resetAPIBaseURLToProduction() async {
        AppConfig.resetToProduction()
        await APIClient.shared.applyConfiguredBaseURL()
        await clearSessionLocally()
    }

    // MARK: - Token persistence (Keychain + UserDefaults migration)

    /// Prefer Keychain; migrate any legacy UserDefaults token once.
    private func loadToken() -> String? {
        if let fromKeychain = KeychainStore.get(account: tokenKey), !fromKeychain.isEmpty {
            return fromKeychain
        }
        guard let legacy = UserDefaults.standard.string(forKey: tokenKey), !legacy.isEmpty else {
            return nil
        }
        // One-time migrate: write to Keychain, then drop insecure UserDefaults copy.
        if KeychainStore.set(legacy, account: tokenKey) {
            UserDefaults.standard.removeObject(forKey: tokenKey)
        }
        return legacy
    }

    private func persistToken(_ value: String) {
        _ = KeychainStore.set(value, account: tokenKey)
        // Ensure no stale plaintext copy remains after upgrades.
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    private func clearPersistedToken() {
        KeychainStore.delete(account: tokenKey)
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}
