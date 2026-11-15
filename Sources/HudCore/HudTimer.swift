import Foundation

/// The clock app's timer: counts down from a set time, or up from zero as a stopwatch.
///
/// Kept as start time plus what ran before, never as a ticking counter, so it stays right
/// however late or irregular the ticks that read it are.
public struct HudTimer: Sendable, Equatable {
    /// What it counts down from. Zero makes it a stopwatch.
    public private(set) var setSeconds: Int
    private var startedAt: Date?
    private var banked: TimeInterval = 0

    public init(setSeconds: Int = 300) {
        self.setSeconds = max(setSeconds, 0)
    }

    public var isRunning: Bool { startedAt != nil }
    /// Never started since the last reset: the set time can still change.
    public var isIdle: Bool { startedAt == nil && banked == 0 }

    public func elapsed(at now: Date) -> TimeInterval {
        banked + (startedAt.map { now.timeIntervalSince($0) } ?? 0)
    }

    public func isDone(at now: Date) -> Bool {
        setSeconds > 0 && elapsed(at: now) >= Double(setSeconds)
    }

    /// Start, or pause. A finished timer starts over.
    public mutating func toggle(at now: Date) {
        if isDone(at: now) {
            reset()
            startedAt = now
        } else if let startedAt {
            banked += now.timeIntervalSince(startedAt)
            self.startedAt = nil
        } else {
            startedAt = now
        }
    }

    public mutating func reset() {
        startedAt = nil
        banked = 0
    }

    /// The wheel over an idle timer: a minute a notch under ten minutes, five above.
    public mutating func adjust(notches: Int) {
        guard isIdle, notches != 0 else { return }
        var minutes = setSeconds / 60
        for _ in 0..<abs(notches) {
            if notches > 0 {
                minutes += minutes >= 10 ? 5 : 1
            } else {
                minutes -= minutes > 10 ? 5 : 1
            }
        }
        setSeconds = min(max(minutes, 0), 180) * 60
    }

    public func reading(at now: Date) -> HudSnapshot.TimerReading {
        var reading = HudSnapshot.TimerReading()
        let elapsed = elapsed(at: now)
        reading.isStopwatch = setSeconds == 0
        if reading.isStopwatch {
            reading.text = Self.format(elapsed)
            reading.progress = nil
        } else {
            let remaining = max(Double(setSeconds) - elapsed, 0)
            // Rounded up, so 4:59.2 reads 5:00 and it only says 0:00 when it is over.
            reading.text = Self.format(remaining.rounded(.up))
            reading.progress = min(elapsed / Double(setSeconds), 1)
        }
        if isDone(at: now) {
            reading.state = .done
        } else if isRunning {
            reading.state = .running
        } else {
            reading.state = isIdle ? .idle : .paused
        }
        return reading
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
