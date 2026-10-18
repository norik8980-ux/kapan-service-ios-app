import CoreLocation
import Foundation

/// Posts GPS while a plumber job is active (`en_route`).
/// Approach SMS (3 miles) is computed server-side on each ping.
@MainActor
final class LocationPublisher: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var isSharing = false
    @Published var activeBookingId: String?
    @Published var lastError: String?
    @Published var lastDistanceMiles: Double?
    @Published var lastApproachSent = false
    /// Latest booking payload from a location POST (auto-arrived status, etc.).
    @Published var lastBookingSnapshot: MobileBooking?
    /// Set when a location POST returns 401 so the UI can sign out.
    @Published var sessionExpired = false

    private let manager = CLLocationManager()
    private var lastPostAt: Date?
    private let minPostInterval: TimeInterval = 8

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
        sessionExpired = false
        lastPostAt = nil
        requestPermissionIfNeeded()
        manager.startUpdatingLocation()
    }

    func stop() {
        activeBookingId = nil
        isSharing = false
        lastDistanceMiles = nil
        lastPostAt = nil
        manager.stopUpdatingLocation()
    }

    /// Resume sharing when a plumber reopens an en-route job.
    func sync(with booking: MobileBooking, isPlumber: Bool) {
        guard isPlumber, booking.status == "en_route" else {
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
            if let last = lastPostAt, Date().timeIntervalSince(last) < minPostInterval {
                return
            }
            lastPostAt = Date()
            do {
                let result = try await APIClient.shared.postLocation(
                    bookingId: bookingId,
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude
                )
                lastDistanceMiles = result.distanceMiles
                lastBookingSnapshot = result.booking
                if result.approach?.sent == true {
                    lastApproachSent = true
                }
                // Arrival is automatic at ~3 mi — stop sharing once server marks arrived.
                if result.approach?.autoArrived == true
                    || result.booking.status == "arrived"
                    || result.booking.status == "completed"
                    || result.booking.status == "canceled" {
                    stop()
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                if let api = error as? APIError, case .unauthorized = api {
                    sessionExpired = true
                    stop()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}
