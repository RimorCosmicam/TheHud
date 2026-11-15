import Foundation
import CoreLocation

/// Where the wearer is, which way they are facing, and how fast they are moving.
///
/// Heading rather than course on purpose: the map rotates to the way the head is pointing, and
/// course is only meaningful while actually moving. Standing still with a course of zero would
/// snap the map north, which is exactly when a rotating map is most disorienting.
public final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastGeocode: Date = .distantPast
    private var placeName: String?

    /// Called on the main queue whenever anything changes.
    public var onUpdate: ((HudSnapshot.Minimap, CLLocationCoordinate2D) -> Void)?

    public private(set) var coordinate: CLLocationCoordinate2D?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Ten metres of movement is about the resolution a 300m minimap can show anyway.
        manager.distanceFilter = 10
    }

    public func start() {
        #if os(iOS)
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        #endif
    }

    public func stop() {
        manager.stopUpdatingLocation()
        #if os(iOS)
        manager.stopUpdatingHeading()
        #endif
    }

    private var heading: Double = 0

    public func locationManager(_ manager: CLLocationManager,
                                didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        reverseGeocodeIfStale(location)
        publish(location)
    }

    #if os(iOS)
    public func locationManager(_ manager: CLLocationManager,
                                didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if let location = manager.location { publish(location) }
    }
    #endif

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A HUD that cannot place you still tells the time. Nothing to do but leave the panel be.
    }

    private func publish(_ location: CLLocation) {
        let speed = max(location.speed, 0) * 3.6
        let minimap = HudSnapshot.Minimap(
            place: (placeName ?? "").uppercased(),
            heading: heading,
            headingLabel: Self.compass(heading),
            speed: String(format: "%.1f KM/H", speed),
            spanMetres: 300)

        let coordinate = location.coordinate
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(minimap, coordinate)
        }
    }

    /// Reverse geocoding is rate limited by the system, and a neighbourhood name does not change
    /// as you cross a street. Once a minute is plenty.
    private func reverseGeocodeIfStale(_ location: CLLocation) {
        guard Date().timeIntervalSince(lastGeocode) > 60 else { return }
        lastGeocode = Date()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            self?.placeName = placemark.subLocality ?? placemark.locality ?? placemark.name ?? ""
        }
    }

    static func compass(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees.truncatingRemainder(dividingBy: 360) / 45).rounded()) % 8
        return points[max(index, 0)]
    }
}
