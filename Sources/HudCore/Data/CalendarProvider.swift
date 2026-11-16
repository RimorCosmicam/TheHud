import Foundation
import EventKit

/// The next thing in the calendar.
///
/// Access is a prompt the user answers once. Without it the clock panel simply shows the time and
/// date, which is why `nextEvent` is optional all the way through the model rather than a string
/// that says "no access" — a HUD should drop a line it cannot fill, not explain itself.
@MainActor
public final class CalendarProvider {
    let store = EKEventStore()

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

extension CalendarProvider {
    /// The calendar app: today as a timeline, what is next, and the month around it.
    public func agendaApp(now: Date = Date()) -> HudSnapshot.Agenda {
        var agenda = HudSnapshot.Agenda()
        let calendar = Calendar.current
        let fixed = { (format: String) -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
        let localised = { (format: String) -> DateFormatter in
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate(format)
            return formatter
        }
        let uses24Hour = (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "H").contains("H")
        let time = fixed(uses24Hour ? "H:mm" : "h:mm")
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        agenda.nowMinute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        agenda.dayTitle = (localised("EEEE").string(from: now) + " \u{00B7} " + localised("d MMMM").string(from: now))
            .uppercased()
        agenda.monthTitle = localised("MMMM yyyy").string(from: now).uppercased()

        // Weeks as the phone's calendar starts them.
        let symbols = fixed("EEE").shortWeekdaySymbols.map { $0.uppercased() }
        let first = calendar.firstWeekday - 1
        agenda.weekdays = (0..<7).map { symbols[(first + $0) % 7] }

        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            agenda.hasAccess = false
            agenda.days = Self.monthDays(around: now, calendar: calendar, events: [])
            return agenda
        }

        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let month = calendar.dateInterval(of: .month, for: now),
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start,
              let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart) else { return agenda }

        let events = store.events(matching: store.predicateForEvents(withStart: gridStart, end: gridEnd, calendars: nil))
        // A tint per calendar, in the order they first turn up.
        var tints: [String: Int] = [:]
        func tint(_ event: EKEvent) -> Int {
            let id = event.calendar?.calendarIdentifier ?? ""
            if let tint = tints[id] { return tint }
            tints[id] = tints.count
            return tints[id]!
        }
        let minute = { (date: Date) -> Int in
            if date <= dayStart { return 0 }
            if date >= dayEnd { return 24 * 60 }
            let p = calendar.dateComponents([.hour, .minute], from: date)
            return (p.hour ?? 0) * 60 + (p.minute ?? 0)
        }
        let today = events.filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        agenda.today = today.map { event in
            HudSnapshot.Agenda.Entry(
                title: event.title ?? "",
                time: event.isAllDay ? "ALL DAY" : time.string(from: event.startDate),
                endTime: event.isAllDay ? "" : time.string(from: event.endDate),
                startMinute: event.isAllDay ? 0 : minute(event.startDate),
                endMinute: event.isAllDay ? 24 * 60 : minute(event.endDate),
                allDay: event.isAllDay, location: event.location ?? "", tint: tint(event))
        }
        let timed = zip(today, agenda.today).filter { !$0.0.isAllDay && $0.0.endDate > now }
        if let (event, entry) = timed.first {
            agenda.next = entry
            if event.startDate <= now {
                agenda.nextIn = "NOW"
            } else {
                let minutes = Int(event.startDate.timeIntervalSince(now) / 60)
                agenda.nextIn = minutes < 60 ? "IN \(max(minutes, 1)) MIN"
                    : minutes < 180 ? "IN \(minutes / 60) H \(minutes % 60) MIN" : "AT \(entry.time)"
            }
            agenda.later = timed.dropFirst().prefix(3).map(\.1)
        }
        agenda.days = Self.monthDays(around: now, calendar: calendar, events: events)
        return agenda
    }

    /// Whole weeks covering the month, each day with its first few events.
    static func monthDays(around now: Date, calendar: Calendar, events: [EKEvent]) -> [HudSnapshot.Agenda.Day] {
        guard let month = calendar.dateInterval(of: .month, for: now),
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: month.start)?.start else { return [] }
        let lastDay = month.end.addingTimeInterval(-1)
        var days: [HudSnapshot.Agenda.Day] = []
        var day = gridStart
        while days.count < 42 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let titles = events.filter { $0.startDate < next && $0.endDate > day }
                .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
                .compactMap(\.title)
            days.append(HudSnapshot.Agenda.Day(
                number: calendar.component(.day, from: day),
                inMonth: calendar.isDate(day, equalTo: now, toGranularity: .month),
                isToday: calendar.isDate(day, inSameDayAs: now),
                titles: Array(titles.prefix(3)), more: max(titles.count - 3, 0)))
            // Stop at the end of the week the month ends in: 35 days, or 42.
            if day > lastDay, days.count % 7 == 0 { break }
            day = next
        }
        return days
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
