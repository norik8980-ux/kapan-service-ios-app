import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: MobileUser?
    @Published var token: String?
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
        guard let saved = UserDefaults.standard.string(forKey: tokenKey), !saved.isEmpty else {
            return
        }
        token = saved
        await APIClient.shared.setToken(saved)
        do {
            user = try await APIClient.shared.me()
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
        UserDefaults.standard.set(response.token, forKey: tokenKey)
        await APIClient.shared.setToken(response.token)
        PushRegistration.shared.setSignedIn(true)
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
        UserDefaults.standard.removeObject(forKey: tokenKey)
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
}
