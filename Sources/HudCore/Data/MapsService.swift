import Foundation
import MapKit

/// Search and directions, from Apple Maps. MapKit on both platforms, so the preview tool can run
/// a real search on a Mac.
@MainActor
public final class MapsService {
    public init() {}

    public struct Result: @unchecked Sendable {
        public var item: MKMapItem
        public var place: HudSnapshot.Maps.Place
    }

    /// Places matching what was typed, nearest first, within reach of where the wearer is.
    public func search(_ query: String, near here: CLLocationCoordinate2D) async throws -> [Result] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: here, latitudinalMeters: 20_000,
                                            longitudinalMeters: 20_000)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
            .map { item -> (MKMapItem, Double) in
                (item, NavigationTracker.metres(here, item.placemark.coordinate))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(5)
            .map { item, metres in
                let placemark = item.placemark
                let street = [placemark.thoroughfare, placemark.subThoroughfare]
                    .compactMap { $0 }.joined(separator: " ")
                let detail = street.isEmpty
                    ? (placemark.locality ?? placemark.title ?? "") : street
                return Result(item: item,
                              place: .init(name: item.name ?? placemark.title ?? "",
                                           detail: detail,
                                           distance: NavigationTracker.distanceText(metres)))
            }
    }

    public func route(from here: CLLocationCoordinate2D, to destination: MKMapItem,
                      driving: Bool) async throws -> RoutePlan {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: here))
        request.destination = destination
        request.transportType = driving ? .automobile : .walking
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw MapsError.noRoute }

        func coordinates(_ line: MKPolyline) -> [CLLocationCoordinate2D] {
            var points = [CLLocationCoordinate2D](repeating: .init(), count: line.pointCount)
            line.getCoordinates(&points, range: NSRange(location: 0, length: line.pointCount))
            return points
        }

        return RoutePlan(
            destination: destination.name ?? "",
            points: coordinates(route.polyline),
            steps: route.steps.map { step in
                RoutePlan.Step(instruction: step.instructions,
                               point: coordinates(step.polyline).first ?? here,
                               distance: step.distance)
            },
            expectedTravelTime: route.expectedTravelTime,
            distance: route.distance)
    }

    public enum MapsError: Error { case noRoute }
}
