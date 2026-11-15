import Foundation
import CoreLocation

/// A route as the HUD needs it: the line to draw, and the turns along it. Built from an
/// `MKRoute` on the device, or by hand in a test.
public struct RoutePlan: Sendable {
    public struct Step: Sendable {
        public var instruction: String
        /// Where the turn is: the first point of the step's line.
        public var point: CLLocationCoordinate2D
        /// Metres from this turn to the next.
        public var distance: Double
        public init(instruction: String, point: CLLocationCoordinate2D, distance: Double) {
            self.instruction = instruction
            self.point = point
            self.distance = distance
        }
    }

    public var destination: String
    public var points: [CLLocationCoordinate2D]
    public var steps: [Step]
    public var expectedTravelTime: TimeInterval
    public var distance: Double

    public init(destination: String, points: [CLLocationCoordinate2D], steps: [Step],
                expectedTravelTime: TimeInterval, distance: Double) {
        self.destination = destination
        self.points = points
        self.steps = steps
        self.expectedTravelTime = expectedTravelTime
        self.distance = distance
    }
}

/// Follows the wearer along a route: which turn is next, how far to it, how long is left.
public struct NavigationTracker: Sendable {
    public let plan: RoutePlan
    /// The next turn to make.
    public private(set) var stepIndex: Int

    /// Within this many metres of a turn, it counts as made.
    public static let turnRadius: Double = 20
    public static let arrivalRadius: Double = 25

    public init(plan: RoutePlan) {
        self.plan = plan
        // The first step is "start here", with no instruction.
        stepIndex = plan.steps.firstIndex { !$0.instruction.isEmpty } ?? max(plan.steps.count - 1, 0)
    }

    public mutating func update(at here: CLLocationCoordinate2D,
                                now: Date = Date(),
                                locale: Locale = .current) -> HudSnapshot.Maps.Navigation {
        while stepIndex < plan.steps.count - 1,
              Self.metres(here, plan.steps[stepIndex].point) < Self.turnRadius {
            stepIndex += 1
        }

        let toTurn = plan.steps.isEmpty ? 0 : Self.metres(here, plan.steps[stepIndex].point)
        let after = plan.steps.isEmpty ? 0
            : plan.steps[stepIndex...].reduce(0) { $0 + $1.distance }
        let remaining = toTurn + after
        let seconds = plan.distance > 0
            ? plan.expectedTravelTime * min(remaining / plan.distance, 1.5) : 0
        let arrived = plan.points.last.map { Self.metres(here, $0) < Self.arrivalRadius } ?? false

        let instruction = plan.steps.isEmpty ? plan.destination : plan.steps[stepIndex].instruction
        let uses24Hour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)
                          ?? "H").contains("H")
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = uses24Hour ? "H:mm" : "h:mm"

        var navigation = HudSnapshot.Maps.Navigation(
            destination: plan.destination,
            instruction: arrived ? "You have arrived" : instruction,
            maneuver: arrived ? "mappin.and.ellipse" : Self.maneuverSymbol(instruction),
            stepDistance: Self.distanceText(toTurn),
            remainingTime: Self.durationText(seconds),
            remainingDistance: Self.distanceText(remaining),
            arrival: clock.string(from: now.addingTimeInterval(seconds)))
        navigation.arrived = arrived
        return navigation
    }

    // ------------------------------------------------------------------ formatting

    public static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// "40 M", "850 M", "2.4 KM".
    public static func distanceText(_ metres: Double) -> String {
        if metres < 1000 {
            let rounded = metres < 100 ? (metres / 5).rounded() * 5 : (metres / 10).rounded() * 10
            return "\(Int(rounded)) M"
        }
        return String(format: metres < 10_000 ? "%.1f KM" : "%.0f KM", metres / 1000)
    }

    /// "1 MIN", "12 MIN", "1 H 05".
    public static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded()), 1)
        if minutes < 60 { return "\(minutes) MIN" }
        return String(format: "%d H %02d", minutes / 60, minutes % 60)
    }

    /// A turn arrow from the instruction's words. MapKit gives text, not a maneuver type, and
    /// in the phone's language, so English, Portuguese and Spanish are all read.
    public static func maneuverSymbol(_ instruction: String) -> String {
        let text = instruction.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }
        if has(["u-turn", "make a u", "retorno", "meia-volta", "cambio de sentido", "media vuelta"]) {
            return "arrow.uturn.down"
        }
        if has(["roundabout", "rotunda", "rotatória", "rotatoria", "glorieta"]) {
            return "arrow.triangle.turn.up.right.circle"
        }
        if has(["destination", "arrive", "destino", "chegada", "llegada"]) {
            return "mappin.and.ellipse"
        }
        let slight = has(["slight", "bear", "ligeiramente", "levemente", "ligeramente", "mantenha"])
        if has(["left", "esquerda", "izquierda"]) {
            return slight ? "arrow.up.left" : "arrow.turn.up.left"
        }
        if has(["right", "direita", "derecha"]) {
            return slight ? "arrow.up.right" : "arrow.turn.up.right"
        }
        return "arrow.up"
    }
}
