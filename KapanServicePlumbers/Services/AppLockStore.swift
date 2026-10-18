import Foundation
import LocalAuthentication
import SwiftUI

/// Scope A: require Face ID (or device passcode) after background / cold start.
/// Does not replace server password login.
@MainActor
final class AppLockStore: ObservableObject {
    static let shared = AppLockStore()

    private static let enabledKey = "kapan.faceid.unlock.enabled"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var isLocked = false
    @Published private(set) var biometryAvailable = false
    @Published private(set) var lastError: String?

    private var signedIn = false

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        refreshBiometryAvailability()
    }

    var unavailableMessage: String? {
        biometryAvailable ? nil : "Face ID isn’t available on this device."
    }

    func setSignedIn(_ value: Bool) {
        signedIn = value
        if !value {
            isLocked = false
            lastError = nil
            return
        }
        // Fresh password login stays unlocked; cold restore may lock below.
    }

    /// Call after session restore on cold start when Face ID is on.
    func lockIfNeededForColdStart() {
        guard signedIn, isEnabled, biometryAvailable else {
            isLocked = false
            return
        }
        isLocked = true
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard signedIn, isEnabled, biometryAvailable else { return }
        switch phase {
        case .background, .inactive:
            // Lock when leaving the foreground so return requires biometry.
            if phase == .background {
                isLocked = true
            }
        case .active:
            if isLocked {
                Task { await unlock() }
            }
        @unknown default:
            break
        }
    }

    func setEnabled(_ on: Bool) {
        refreshBiometryAvailability()
        if on, !biometryAvailable {
            lastError = unavailableMessage
            isEnabled = false
            return
        }
        isEnabled = on
        lastError = nil
        if !on {
            isLocked = false
        }
    }

    func unlock() async {
        guard isLocked else { return }
        refreshBiometryAvailability()
        guard biometryAvailable else {
            lastError = unavailableMessage
            // Fail open if hardware disappears — don’t trap the user.
            isLocked = false
            return
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lastError = error?.localizedDescription ?? unavailableMessage
            isLocked = false
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Kapan Service Plumbers"
            )
            if ok {
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
            // Stay locked; user can retry from the lock screen.
        }
    }

    func refreshBiometryAvailability() {
        let context = LAContext()
        var error: NSError?
        biometryAvailable = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
}
