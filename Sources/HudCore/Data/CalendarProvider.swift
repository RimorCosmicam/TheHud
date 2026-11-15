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

    /// What is left of today: what is on now, then what is still to come.
    public func agenda(now: Date = Date(), limit: Int = 6) -> [HudSnapshot.Clock.Event] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end,
                                                                      calendars: nil))
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let uses24Hour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0,
                                                   locale: .current) ?? "H").contains("H")
        formatter.dateFormat = uses24Hour ? "H:mm" : "h:mm"
        return events.prefix(limit).map { event in
            HudSnapshot.Clock.Event(
                title: event.title ?? "",
                time: event.isAllDay ? "ALL DAY" : formatter.string(from: event.startDate),
                end: event.isAllDay ? nil : formatter.string(from: event.endDate),
                isNow: !event.isAllDay && event.startDate <= now)
        }
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

        var clock = HudSnapshot.Clock(
            time: fixed(uses24Hour ? "HH:mm" : "h:mm").string(from: date),
            meridiem: uses24Hour ? nil : fixed("a").string(from: date),
            weekday: localised("EEEE").string(from: date).uppercased(),
            date: localised("d MMMM").string(from: date).uppercased())

        let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond],
                                                    from: date)
        let second = Double(parts.second ?? 0)
        let minute = Double(parts.minute ?? 0) + second / 60
        clock.seconds = String(format: "%02d", parts.second ?? 0)
        clock.secondHand = second
        clock.minuteHand = minute
        clock.hourHand = Double((parts.hour ?? 0) % 12) + minute / 60

        clock.worldClocks = worldCities.map { city, zone in
            HudSnapshot.Clock.worldClock(city, zone, at: date, uses24Hour: uses24Hour)
        }
        return clock
    }

    /// The other places on the clock app. A fixed set for now; the useful three for most people.
    static let worldCities: [(String, TimeZone)] = [
        ("NEW YORK", TimeZone(identifier: "America/New_York")!),
        ("LONDON", TimeZone(identifier: "Europe/London")!),
        ("TOKYO", TimeZone(identifier: "Asia/Tokyo")!),
    ]

    static func worldClock(_ city: String, _ zone: TimeZone, at date: Date,
                           uses24Hour: Bool, here: TimeZone = .current) -> WorldClock {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = uses24Hour ? "H:mm" : "h:mm a"
        let hours = Double(zone.secondsFromGMT(for: date) - here.secondsFromGMT(for: date)) / 3600
        let sign = hours < 0 ? "\u{2212}" : "+"
        let magnitude = abs(hours)
        let amount = magnitude == magnitude.rounded() ? String(Int(magnitude))
            : String(format: "%.1f", magnitude)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        return WorldClock(city: city, time: formatter.string(from: date),
                          offset: hours == 0 ? "SAME TIME" : "\(sign)\(amount)H",
                          isDay: (7..<19).contains(hour))
    }
}
