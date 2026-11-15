import Foundation
import EventKit

/// The next thing in the calendar.
///
/// Access is a prompt the user answers once. Without it the clock panel simply shows the time and
/// date, which is why `nextEvent` is optional all the way through the model rather than a string
/// that says "no access" — a HUD should drop a line it cannot fill, not explain itself.
@MainActor
public final class CalendarProvider {
    private let store = EKEventStore()

    public init() {}

    public func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// The next event starting within `window`, ignoring all-day events — an all-day event is not
    /// a thing that is about to happen.
    public func nextEvent(within window: TimeInterval = 12 * 3600,
                          now: Date = Date()) -> (title: String, time: String)? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }

        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(window),
                                                 calendars: nil)
        let next = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now }
            .min { $0.startDate < $1.startDate }

        guard let next, let title = next.title else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return (title, formatter.string(from: next.startDate))
    }
}

public extension HudSnapshot.Clock {
    /// The clock is the one panel that needs no permission and no network.
    static func now(_ date: Date = Date(), calendar: Calendar = .current) -> HudSnapshot.Clock {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"

        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"

        let day = DateFormatter()
        day.dateFormat = "d MMMM"

        return HudSnapshot.Clock(time: time.string(from: date),
                                 weekday: weekday.string(from: date).uppercased(),
                                 date: day.string(from: date).uppercased())
    }
}
