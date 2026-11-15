#if os(iOS)
import Foundation
import CoreMotion

/// Steps, distance and floors today, from the phone's motion coprocessor. No HealthKit: that
/// needs an entitlement a sideloaded build does not carry, and the pedometer answers the same
/// question for the phone in the pocket.
@MainActor
public final class ActivityProvider {
    public var onChange: ((HudSnapshot.Activity?) -> Void)?
    public var goal = 8000

    private let pedometer = CMPedometer()
    private var started = false
    private var day: Date?
    private var current = HudSnapshot.Activity(steps: 0)
    private var lastHourly: Date = .distantPast

    public init() {}

    public func start() {
        guard !started else { return }
        started = true
        guard CMPedometer.isStepCountingAvailable() else { return onChange?(nil) }
        restart()
    }

    /// Called every second with the clock; cheap unless the day has turned or the hours need
    /// refreshing.
    public func tick(now: Date = Date()) {
        guard started, let day else { return }
        if !Calendar.current.isDate(now, inSameDayAs: day) {
            restart()
        } else if now.timeIntervalSince(lastHourly) > 300 {
            refreshHours(now: now)
        }
    }

    private func restart() {
        pedometer.stopUpdates()
        let midnight = Calendar.current.startOfDay(for: Date())
        day = midnight
        current = HudSnapshot.Activity(steps: 0, goal: goal)
        pedometer.startUpdates(from: midnight) { [weak self] data, _ in
            guard let data else { return }
            let steps = data.numberOfSteps.intValue
            let km = data.distance.map { $0.doubleValue / 1000 }
            let floors = data.floorsAscended?.intValue
            Task { @MainActor in
                guard let self else { return }
                self.current.steps = steps
                self.current.distanceKm = km
                self.current.floors = floors
                self.current.goal = self.goal
                self.publish()
            }
        }
        refreshHours(now: Date())
    }

    /// Steps in each hour since midnight, for the app's bars.
    private func refreshHours(now: Date) {
        lastHourly = now
        let midnight = Calendar.current.startOfDay(for: now)
        let hours = Int(now.timeIntervalSince(midnight) / 3600) + 1
        var counts = Array(repeating: 0, count: hours)
        let group = DispatchGroup()
        let lock = NSLock()
        for hour in 0..<hours {
            let from = midnight.addingTimeInterval(Double(hour) * 3600)
            let to = min(from.addingTimeInterval(3600), now)
            group.enter()
            pedometer.queryPedometerData(from: from, to: to) { data, _ in
                lock.lock()
                counts[hour] = data?.numberOfSteps.intValue ?? 0
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                self?.current.hourly = counts
                self?.publish()
            }
        }
    }

    private func publish() { onChange?(current) }
}
#endif
