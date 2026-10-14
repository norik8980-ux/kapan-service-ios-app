import CoreLocation
import Foundation

/// Posts GPS while a plumber job is active (assigned / en_route).
@MainActor
final class LocationPublisher: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var lastError: String?

    private let manager = CLLocationManager()
    private var bookingId: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        authorization = manager.authorizationStatus
    }

    func start(bookingId: String) {
        self.bookingId = bookingId
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        bookingId = nil
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorization = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            guard let bookingId else { return }
            do {
                try await APIClient.shared.postLocation(
                    bookingId: bookingId,
                    lat: loc.coordinate.latitude,
                    lng: loc.coordinate.longitude
                )
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
