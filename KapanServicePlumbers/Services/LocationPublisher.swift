import CoreLocation
import Foundation

/// Posts GPS while a plumber job is active (`assigned` / `en_route`).
/// Approach SMS (3 miles) is computed server-side on each ping.
@MainActor
final class LocationPublisher: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var isSharing = false
    @Published var activeBookingId: String?
    @Published var lastError: String?
    @Published var lastDistanceMiles: Double?
    @Published var lastApproachSent = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 40
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus
    }

    var permissionDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestPermissionIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func start(bookingId: String) {
        activeBookingId = bookingId
        isSharing = true
        lastError = nil
        lastApproachSent = false
        requestPermissionIfNeeded()
        // Keep updates while the app is in use during an active job.
        manager.startUpdatingLocation()
    }

    func stop() {
        activeBookingId = nil
        isSharing = false
        lastDistanceMiles = nil
        manager.stopUpdatingLocation()
    }

    /// Resume sharing when reopening an en-route job.
    func sync(with booking: MobileBooking, isPlumber: Bool) {
        guard isPlumber, booking.isActiveFieldJob, booking.status == "en_route" else {
            if activeBookingId == booking.id {
                stop()
            }
            return
        }
        if activeBookingId != booking.id || !isSharing {
            start(bookingId: booking.id)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
            if self.isSharing, self.activeBookingId != nil,
               manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            guard let bookingId = activeBookingId, isSharing else { return }
            do {
                let result = try await APIClient.shared.postLocation(
                    bookingId: bookingId,
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude
                )
                lastDistanceMiles = result.distanceMiles
                if result.approach?.sent == true {
                    lastApproachSent = true
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}
