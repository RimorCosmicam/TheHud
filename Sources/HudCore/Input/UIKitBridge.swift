#if canImport(UIKit)
import UIKit

/// Turns UIKit touches into `TouchFrame`s for the recogniser.
///
/// Two things matter. First, UIKit has no stable pointer index, so identity is kept by
/// `ObjectIdentifier` and handed out as small integers the way Android numbers its pointers.
/// Second, `coalescedTouches` is the direct analogue of Android's historical events: the digitiser
/// samples faster than the screen refreshes, and consuming the in-between samples is most of why
/// pointer motion feels attached to the finger rather than to the frame clock.
public final class UIKitTouchBridge {
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextId = 0
    private let recognizer: GestureRecognizer
    /// Touches the pad does not own — the rail and the corner take theirs before the recogniser
    /// sees them, so a thumb on the rail and a finger on the pad never merge into one gesture.
    public var owns: (UITouch) -> Bool = { _ in true }

    public init(recognizer: GestureRecognizer) {
        self.recognizer = recognizer
    }

    private func id(for touch: UITouch) -> Int {
        let key = ObjectIdentifier(touch)
        if let existing = ids[key] { return existing }
        ids[key] = nextId
        nextId += 1
        return ids[key]!
    }

    private func point(_ touch: UITouch, in view: UIView) -> TouchPoint {
        let location = touch.location(in: view)
        return TouchPoint(x: location.x, y: location.y, id: id(for: touch),
                          pressure: touch.force > 0 ? touch.force : 1)
    }

    /// Every pointer currently down, in a stable order so index 0 stays index 0.
    private func ordered(_ event: UIEvent?, in view: UIView) -> [TouchPoint] {
        let all = (event?.touches(for: view) ?? []).filter { $0.phase != .cancelled && owns($0) }
        return all.map { point($0, in: view) }.sorted { $0.id < $1.id }
    }

    private static func ms(_ timestamp: TimeInterval) -> Double { timestamp * 1000 }

    public func began(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        let touches = touches.filter(owns)
        guard !touches.isEmpty else { return }
        let all = ordered(event, in: view)
        let action: TouchAction = all.count == touches.count ? .down : .pointerDown
        recognizer.handle(TouchFrame(action: action, touches: all,
                                     timeMs: Self.ms(touches.first?.timestamp ?? 0)))
    }

    public func moved(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        let touches = touches.filter(owns)
        guard !touches.isEmpty else { return }
        let all = ordered(event, in: view)
        guard let primary = all.first else { return }

        // Coalesced samples for the pointer that leads the frame.
        var history: [CoalescedSample] = []
        if let leading = touches.first(where: { id(for: $0) == primary.id }) ?? touches.first,
           let coalesced = event?.coalescedTouches(for: leading), coalesced.count > 1 {
            history = coalesced.dropLast().map { sample in
                CoalescedSample(timeMs: Self.ms(sample.timestamp),
                                touches: [point(sample, in: view)])
            }
        }

        recognizer.handle(TouchFrame(action: .move, touches: all,
                                     timeMs: Self.ms(touches.first?.timestamp ?? 0),
                                     history: history))
    }

    public func ended(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        let touches = touches.filter(owns)
        guard !touches.isEmpty else { return }
        let all = ordered(event, in: view)
        let lifting = Set(touches.map { id(for: $0) })
        let remaining = all.filter { !lifting.contains($0.id) }
        let index = all.firstIndex { lifting.contains($0.id) } ?? 0

        recognizer.handle(TouchFrame(action: remaining.isEmpty ? .up : .pointerUp,
                                     touches: all, actionIndex: index,
                                     timeMs: Self.ms(touches.first?.timestamp ?? 0)))
        if remaining.isEmpty { ids.removeAll() }
    }

    public func cancelled(_ touches: Set<UITouch>, with event: UIEvent?, in view: UIView) {
        guard touches.contains(where: owns) else { return }
        recognizer.handle(TouchFrame(action: .cancel, touches: ordered(event, in: view),
                                     timeMs: Self.ms(touches.first?.timestamp ?? 0)))
        ids.removeAll()
    }
}
#endif
