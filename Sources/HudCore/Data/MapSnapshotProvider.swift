import Foundation
import MapKit
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Renders the minimap's ground.
///
/// `MKMapSnapshotter` exists on both platforms, so the preview tool fetches a real map on a Mac
/// and the device fetches the same one. Only the raster comes from here — the route, the heading
/// cone, the scale bar and the north mark stay in `MinimapPanel`, drawn over whatever ground
/// arrives, so a failed or slow snapshot degrades to the procedural grid without losing them.
public struct MapSnapshotProvider: Sendable {
    public init() {}

    public func snapshot(centre: CLLocationCoordinate2D,
                         spanMetres: Double,
                         size: CGSize,
                         scale: CGFloat = 2) async throws -> CGImage {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: centre,
                                            latitudinalMeters: spanMetres,
                                            longitudinalMeters: spanMetres)
        options.size = size
        options.mapType = .mutedStandard      // the least shouting of the three
        options.showsBuildings = true
        options.pointOfInterestFilter = .excludingAll

        // The HUD is dark because black is transparent on the glasses, so the map must be too.
        #if canImport(UIKit)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        options.scale = scale
        #elseif canImport(AppKit)
        options.appearance = NSAppearance(named: .darkAqua)
        #endif

        let snapshot = try await withCheckedThrowingContinuation { continuation in
            MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) {
                snapshot, error in
                if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: error ?? MapError.noSnapshot)
                }
            }
        }

        #if canImport(UIKit)
        guard let image = snapshot.image.cgImage else { throw MapError.noSnapshot }
        return image
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: snapshot.image.size)
        guard let image = snapshot.image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        else { throw MapError.noSnapshot }
        return image
        #endif
    }

    public enum MapError: Error, CustomStringConvertible {
        case noSnapshot
        public var description: String { "the map snapshotter returned nothing" }
    }
}
