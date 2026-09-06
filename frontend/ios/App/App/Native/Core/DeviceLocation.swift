import CoreLocation
import Foundation

/// Where this device is, named the way the app names places: "Warsaw, Poland".
///
/// The weather screens label a reading with where the person *is*. Until now
/// the only answer on file was the transit location typed by hand on the web,
/// which most accounts never set — so the hero fell back to a timezone's city
/// or to the handle. This asks the device instead.
///
/// One fix per app run, not a continuous feed: the screens want a label, not a
/// track, and a subscription would hold the location indicator lit for nothing.
@MainActor
final class DeviceLocation: NSObject, ObservableObject {

    static let shared = DeviceLocation()

    /// "City, Country", or nil until a fix lands — or forever, if the person
    /// says no. Callers fall back to what the profile carries.
    @Published private(set) var placeName: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var hasAsked = false

    override init() {
        super.init()
        manager.delegate = self
        // A city name is the whole output, so street-level accuracy would cost
        // battery and time for digits that get thrown away.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Asks once per app run. Safe to call from every `task` that wants a
    /// place name — the second call is a no-op.
    func start() {
        guard !hasAsked else { return }
        hasAsked = true

        switch manager.authorizationStatus {
        case .notDetermined:
            // The fix is requested from the authorization callback instead:
            // asking before the person has answered returns nothing.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            NSLog("[Location] not authorised (\(manager.authorizationStatus.rawValue)); keeping the profile's own location")
        @unknown default:
            break
        }
    }

    fileprivate func handle(_ location: CLLocation) {
        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else {
                    NSLog("[Location] reverse geocode returned no placemark")
                    return
                }
                placeName = Self.name(for: placemark)
            } catch {
                NSLog("[Location] reverse geocode failed: \(error.localizedDescription)")
            }
        }
    }

    /// "Warsaw, Poland". Falls back through the administrative area for places
    /// with no locality — open country, and some city states.
    private static func name(for placemark: CLPlacemark) -> String? {
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        let parts = [city, placemark.country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension DeviceLocation: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.handle(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[Location] fix failed: \(error.localizedDescription)")
    }
}
