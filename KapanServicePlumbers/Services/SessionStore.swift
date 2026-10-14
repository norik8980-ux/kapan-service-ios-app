import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published var user: MobileUser?
    @Published var token: String?
    @Published var bootstrapped = false

    private let tokenKey = "kapan.mobile.token"

    init() {
        Task { await restore() }
    }

    var isSignedIn: Bool { token != nil && user != nil }

    func restore() async {
        defer { bootstrapped = true }
        guard let saved = UserDefaults.standard.string(forKey: tokenKey), !saved.isEmpty else {
            return
        }
        token = saved
        await APIClient.shared.setToken(saved)
        do {
            user = try await APIClient.shared.me()
        } catch {
            await signOut()
        }
    }

    func signIn(login: String, password: String) async throws {
        let response = try await APIClient.shared.login(login: login, password: password)
        token = response.token
        user = response.user
        UserDefaults.standard.set(response.token, forKey: tokenKey)
        await APIClient.shared.setToken(response.token)
    }

    func signOut() async {
        token = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: tokenKey)
        await APIClient.shared.setToken(nil)
    }

    /// Clear local session when API returns 401.
    func handleUnauthorized(_ error: Error) async {
        if let api = error as? APIError, case .unauthorized = api {
            await signOut()
        }
    }
}
