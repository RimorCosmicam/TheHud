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
    ///
    /// A fixed `dateFormat` is still interpreted against the user's 12/24-hour setting unless the
    /// formatter's locale is `en_US_POSIX`. With 24-Hour Time off, "HH:mm" comes back as
    /// "1:16 AM" — which is exactly how the time ended up too wide and wrapped onto two lines.
    ///
    /// So: ask the locale which convention it wants, format the time without a meridiem, and hand
    /// the meridiem back separately. The panel already draws it smaller beside the digits, which
    /// is what a 12-hour clock should look like anyway.
    static func now(_ date: Date = Date(), locale: Locale = .current) -> HudSnapshot.Clock {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "H"
        let uses24Hour = template.contains("H")

        let fixed = { (format: String) -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }

        let localised = { (format: String) -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = format
            return formatter
        }

        return HudSnapshot.Clock(
            time: fixed(uses24Hour ? "HH:mm" : "h:mm").string(from: date),
            meridiem: uses24Hour ? nil : fixed("a").string(from: date),
            weekday: localised("EEEE").string(from: date).uppercased(),
            date: localised("d MMMM").string(from: date).uppercased())
    }
}
