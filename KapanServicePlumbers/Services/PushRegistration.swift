import Foundation
import UIKit
import UserNotifications

/// Holds pending deep-link booking ids from notification taps.
@MainActor
final class PushRouter: ObservableObject {
    static let shared = PushRouter()

    @Published var pendingBookingId: String?

    func open(bookingId: String) {
        let trimmed = bookingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingBookingId = trimmed
    }

    func consumePendingBookingId() -> String? {
        let id = pendingBookingId
        pendingBookingId = nil
        return id
    }
}

/// Requests notification permission, registers for APNs, uploads token to `/api/mobile/devices`.
@MainActor
final class PushRegistration: ObservableObject {
    static let shared = PushRegistration()

    @Published private(set) var lastError: String?
    @Published private(set) var deviceTokenHex: String?

    private let tokenDefaultsKey = "kapan.apns.deviceToken"
    private var signedIn = false

    func setSignedIn(_ value: Bool) {
        signedIn = value
        if value {
            requestPermissionAndRegister()
            if let existing = deviceTokenHex ?? UserDefaults.standard.string(forKey: tokenDefaultsKey) {
                Task { await uploadToken(existing) }
            }
        }
    }

    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                }
            }
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        deviceTokenHex = hex
        UserDefaults.standard.set(hex, forKey: tokenDefaultsKey)
        guard signedIn else { return }
        Task { await uploadToken(hex) }
    }

    func didFail(error: Error) {
        lastError = error.localizedDescription
        #if DEBUG
        print("[push] register failed:", error)
        #endif
    }

    func handleNotificationPayload(_ userInfo: [AnyHashable: Any]) {
        if let bookingId = userInfo["bookingId"] as? String {
            PushRouter.shared.open(bookingId: bookingId)
            return
        }
        // Nested custom data sometimes lands under aps-adjacent keys only.
        if let bookingId = userInfo["booking_id"] as? String {
            PushRouter.shared.open(bookingId: bookingId)
        }
    }

    func unregisterOnSignOut() async {
        signedIn = false
        let token = deviceTokenHex ?? UserDefaults.standard.string(forKey: tokenDefaultsKey)
        guard let token, !token.isEmpty else { return }
        do {
            try await APIClient.shared.unregisterDevice(token: token)
        } catch {
            #if DEBUG
            print("[push] unregister failed:", error)
            #endif
        }
    }

    private func uploadToken(_ hex: String) async {
        do {
            try await APIClient.shared.registerDevice(token: hex)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            #if DEBUG
            print("[push] upload token failed:", error)
            #endif
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if let payload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in
                PushRegistration.shared.handleNotificationPayload(payload)
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushRegistration.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushRegistration.shared.didFail(error: error)
        }
    }

    // Foreground presentation
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Tap → open job
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            PushRegistration.shared.handleNotificationPayload(userInfo)
        }
        completionHandler()
    }
}
