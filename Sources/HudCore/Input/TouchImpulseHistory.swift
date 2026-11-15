import Foundation

/// Keeps shader impulses independent of platform pointer ids, which are reused between gestures.
///
/// Released impulses stay in the ring until their visual decay has run out. Keeping them forever
/// left a fixed disturbance everywhere the screen had ever been touched; dropping them the
/// instant a finger lifted cut the ripple off mid-animation.
public final class TouchImpulseHistory {
    private let capacity: Int
    private let retentionSeconds: Double

    /// Insertion order, so eviction at capacity takes the oldest impulse rather than an arbitrary
    /// one. Updating an existing impulse must not move it.
    private var order: [Int] = []
    private var history: [Int: TouchPoint] = [:]
    private var activePointers: [Int: Int] = [:]
    private var nextImpulseId = 1

    public init(capacity: Int = 8, retentionSeconds: Double = 1.8) {
        self.capacity = capacity
        self.retentionSeconds = retentionSeconds
    }

    @discardableResult
    public func update(active: [TouchPoint], now: Double) -> [TouchPoint] {
        let activeIds = Set(active.map(\.id))

        // A pointer that is no longer down becomes a decaying impulse. Its clock restarts here,
        // so age measures time since release.
        for pointerId in activePointers.keys where !activeIds.contains(pointerId) {
            guard let impulseId = activePointers.removeValue(forKey: pointerId),
                  var point = history[impulseId] else { continue }
            point.startedAtSeconds = now
            point.active = false
            history[impulseId] = point
        }

        for point in active {
            let impulseId: Int
            if let existing = activePointers[point.id] {
                impulseId = existing
            } else {
                impulseId = nextImpulseId
                nextImpulseId += 1
                activePointers[point.id] = impulseId
            }

            let old = history[impulseId]
            let start = (old?.active ?? false) ? old!.startedAtSeconds : now

            var stored = point
            stored.id = impulseId
            stored.startedAtSeconds = start
            stored.active = true

            if history[impulseId] == nil { order.append(impulseId) }
            history[impulseId] = stored
        }

        for id in order where !(history[id]?.active ?? true) {
            if let point = history[id], now - point.startedAtSeconds > retentionSeconds {
                history[id] = nil
            }
        }
        order.removeAll { history[$0] == nil }

        while order.count > capacity {
            history[order.removeFirst()] = nil
        }

        return order.compactMap { history[$0] }
    }

    public func reset() {
        order.removeAll()
        history.removeAll()
        activePointers.removeAll()
    }
}
