import SwiftUI

// Calendar, Photos and the teleprompter: three apps in all three sizes — a widget in a slot, the
// app in the centre, and fullscreen when held.

extension HudSnapshot {
    /// Today and this month, from the phone's calendars.
    public struct Agenda: Sendable, Equatable {
        /// False until the calendars may be read; the app says so rather than showing nothing.
        public var hasAccess: Bool = true
        /// "MONDAY · 16 NOVEMBER".
        public var dayTitle: String = ""
        /// Today, all-day first, then by start.
        public var today: [Entry] = []
        /// Minutes since midnight, for the timeline's now line.
        public var nowMinute: Int = 0
        /// What comes next (or is on now), and how soon: "IN 25 MIN", "NOW", "AT 18:40".
        public var next: Entry?
        public var nextIn: String = ""
        /// What follows the next one, for the widget.
        public var later: [Entry] = []
        /// "NOVEMBER 2026".
        public var monthTitle: String = ""
        /// "MON" … "SUN", in the order the phone's calendar starts its week.
        public var weekdays: [String] = []
        /// Whole weeks covering the month: 35 or 42 days.
        public var days: [Day] = []

        public init() {}

        public struct Entry: Sendable, Equatable, Hashable {
            public var title: String
            /// "10:30", or "ALL DAY".
            public var time: String
            public var endTime: String
            public var startMinute: Int
            public var endMinute: Int
            public var allDay: Bool
            public var location: String
            /// Which of a few marks it gets, by its calendar.
            public var tint: Int
            public init(title: String, time: String, endTime: String = "", startMinute: Int = 0,
                        endMinute: Int = 0, allDay: Bool = false, location: String = "", tint: Int = 0) {
                self.title = title
                self.time = time
                self.endTime = endTime
                self.startMinute = startMinute
                self.endMinute = endMinute
                self.allDay = allDay
                self.location = location
                self.tint = tint
            }
        }

        public struct Day: Sendable, Equatable, Hashable {
            public var number: Int
            public var inMonth: Bool
            public var isToday: Bool
            /// The first few events' titles.
            public var titles: [String]
            /// How many more there are than titles.
            public var more: Int
            public init(number: Int, inMonth: Bool = true, isToday: Bool = false,
                        titles: [String] = [], more: Int = 0) {
                self.number = number
                self.inMonth = inMonth
                self.isToday = isToday
                self.titles = titles
                self.more = more
            }
        }

        public static let preview: Agenda = {
            var a = Agenda()
            a.dayTitle = "WEDNESDAY \u{00B7} 15 NOVEMBER"
            a.nowMinute = 9 * 60 + 41
            a.today = [
                Entry(title: "Ana's birthday", time: "ALL DAY", allDay: true, tint: 2),
                Entry(title: "Stand-up", time: "09:00", endTime: "09:15", startMinute: 540, endMinute: 555, tint: 0),
                Entry(title: "Design review", time: "10:30", endTime: "11:30", startMinute: 630, endMinute: 690,
                      location: "Room 4", tint: 1),
                Entry(title: "Lunch with Rui", time: "13:00", endTime: "14:00", startMinute: 780, endMinute: 840,
                      location: "Time Out Market", tint: 3),
                Entry(title: "Ship the HUD build", time: "16:00", endTime: "17:30", startMinute: 960, endMinute: 1050, tint: 0),
                Entry(title: "Flight to Porto", time: "18:40", endTime: "19:40", startMinute: 1120, endMinute: 1180,
                      location: "Gate B32", tint: 4),
            ]
            a.next = a.today[2]
            a.nextIn = "IN 49 MIN"
            a.later = [a.today[3], a.today[4]]
            a.monthTitle = "NOVEMBER 2026"
            a.weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
            let sample = [3: ["Dentist"], 7: ["Market"], 10: ["Review", "Gym"], 15: ["Design review", "Lunch with Rui", "Ship"],
                          18: ["Porto"], 19: ["Porto"], 21: ["Dinner"], 24: ["Release"], 27: ["Ana", "Cinema"]]
            a.days = (0..<35).map { cell in
                let n = cell - 5 + 1
                if n < 1 { return Day(number: 26 + cell, inMonth: false) }
                if n > 30 { return Day(number: n - 30, inMonth: false) }
                let titles = sample[n] ?? []
                return Day(number: n, isToday: n == 15, titles: Array(titles.prefix(3)), more: max(titles.count - 3, 0))
            }
            return a
        }()
    }

    /// The phone's photo library, newest first. The pictures themselves come separately, by
    /// index, as they are loaded.
    public struct Photos: Sendable, Equatable {
        public var hasAccess: Bool = true
        public var count: Int = 0
        /// The one shown: the widget's slideshow and the centre.
        public var current: Int = 0
        /// Fullscreen: the gallery's picked photo, the first row shown, and whether it is open.
        public var selected: Int = 0
        public var scrollRow: Int = 0
        public var viewing: Bool = false
        /// "12 OCTOBER 2026 · LISBON", for whichever is shown.
        public var caption: String = ""
        public init() {}

        public static let preview: Photos = {
            var p = Photos()
            p.count = 248
            p.current = 3
            p.selected = 3
            p.caption = "12 OCTOBER 2026"
            return p
        }()
    }

    /// The teleprompter reads the note. Scrolling is worked out from when it last changed, so
    /// the glasses move it smoothly every frame without anything being sent.
    public struct Prompter: Sendable, Equatable {
        public var isRunning: Bool = false
        /// Points a second.
        public var speed: Double = 60
        public var anchorOffset: CGFloat = 0
        public var anchorTime: Date = .distantPast
        public init() {}

        public func offset(at date: Date) -> CGFloat {
            guard isRunning else { return anchorOffset }
            return anchorOffset + CGFloat(date.timeIntervalSince(anchorTime) * speed)
        }

        /// The speed as the phone shows it: 1 to 10.
        public var step: Int { Int((speed / 30).rounded()) }
        public static let speeds: ClosedRange<Double> = 30...300
    }
}

// MARK: - Calendar

/// The marks events get, by calendar: the accent first.
enum AgendaTint {
    static func color(_ tint: Int) -> Color {
        let colors: [Color] = [HudTheme.accent, Color(red: 0.45, green: 0.72, blue: 1.0),
                               Color(red: 0.95, green: 0.45, blue: 0.45), Color(red: 0.45, green: 0.85, blue: 0.55),
                               Color(red: 0.75, green: 0.55, blue: 1.0), Color.white.opacity(0.7)]
        return colors[abs(tint) % colors.count]
    }
}

public struct CalendarWidget: View {
    public var agenda: HudSnapshot.Agenda
    public init(_ agenda: HudSnapshot.Agenda) { self.agenda = agenda }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetLabel(text: "CALENDAR")
                Spacer()
                Text(agenda.nextIn).font(HudTheme.mont(16, .black)).tracking(2)
                    .foregroundStyle(HudTheme.accent)
            }
            if !agenda.hasAccess {
                Spacer()
                Text("Allow Calendars in Settings").font(HudTheme.mont(24, .semibold))
                    .foregroundStyle(HudTheme.inkFaint)
                Spacer()
            } else if let next = agenda.next {
                Spacer(minLength: 6)
                Text(next.title).font(HudTheme.mont(40, .black)).lineLimit(2)
                    .minimumScaleFactor(0.7).foregroundStyle(HudTheme.ink)
                Text(next.allDay ? "ALL DAY" : "\(next.time) \u{2013} \(next.endTime)"
                     + (next.location.isEmpty ? "" : "  \u{00B7}  \(next.location.uppercased())"))
                    .font(HudTheme.mont(18, .black)).tracking(2).lineLimit(1)
                    .foregroundStyle(HudTheme.inkDim).padding(.top, 6)
                Spacer(minLength: 10)
                ForEach(agenda.later.prefix(2), id: \.self) { entry in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 1).fill(AgendaTint.color(entry.tint)).frame(width: 4, height: 26)
                        Text(entry.title).font(HudTheme.mont(22, .semibold)).lineLimit(1)
                            .foregroundStyle(HudTheme.ink)
                        Spacer(minLength: 6)
                        Text(entry.time).font(HudTheme.mont(22, .black)).monospacedDigit()
                            .foregroundStyle(HudTheme.inkDim)
                    }
                    .padding(.top, 6)
                }
            } else {
                Spacer()
                Text("Nothing else today").font(HudTheme.mont(30, .black)).foregroundStyle(HudTheme.inkDim)
                Text(agenda.dayTitle).font(HudTheme.mont(16, .black)).tracking(2)
                    .foregroundStyle(HudTheme.inkFaint).padding(.top, 8)
                Spacer()
            }
        }
        .widgetSurface()
    }
}

/// The day as a timeline: the hours down the side, events as blocks, and a line at now.
public struct CalendarDayView: View {
    public var agenda: HudSnapshot.Agenda
    public var size: CGSize
    public init(_ agenda: HudSnapshot.Agenda, size: CGSize) {
        self.agenda = agenda
        self.size = size
    }

    /// The hours shown: from just before the first thing (or now) to just after the last.
    private var hours: ClosedRange<Int> {
        let timed = agenda.today.filter { !$0.allDay }
        let first = min(timed.map(\.startMinute).min() ?? agenda.nowMinute, agenda.nowMinute) / 60
        let last = (max(timed.map(\.endMinute).max() ?? agenda.nowMinute, agenda.nowMinute) + 59) / 60
        let start = max(0, min(first, 23) - 1)
        var end = min(24, max(last + 1, start + 6))
        if end - start > 16 { end = start + 16 }
        return start...end
    }

    public var body: some View {
        let allDay = agenda.today.filter(\.allDay)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                WidgetLabel(text: "TODAY")
                Spacer()
                Text(agenda.nextIn).font(HudTheme.mont(18, .black)).tracking(2).foregroundStyle(HudTheme.accent)
            }
            Text(agenda.dayTitle).font(HudTheme.mont(44, .black)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(HudTheme.ink).padding(.top, 8)
            if !allDay.isEmpty {
                HStack(spacing: 10) {
                    ForEach(allDay, id: \.self) { entry in
                        Text(entry.title).font(HudTheme.mont(20, .black)).lineLimit(1)
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(AgendaTint.color(entry.tint), in: Capsule())
                    }
                }
                .padding(.top, 14)
            }
            if agenda.hasAccess {
                timeline.padding(.top, 20)
            } else {
                Text("Allow Calendars in Settings to see the day")
                    .font(HudTheme.mont(28, .semibold)).foregroundStyle(HudTheme.inkDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(48)
        .appSurface()
    }

    private var timeline: some View {
        GeometryReader { geometry in
            let range = hours
            let span = CGFloat(range.upperBound - range.lowerBound) * 60
            let perMinute = geometry.size.height / max(span, 60)
            let y = { (minute: Int) in CGFloat(minute - range.lowerBound * 60) * perMinute }
            let gutter: CGFloat = 92
            ZStack(alignment: .topLeading) {
                ForEach(Array(range), id: \.self) { hour in
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", hour % 24)).font(HudTheme.mont(20, .black))
                            .foregroundStyle(HudTheme.inkFaint).frame(width: gutter - 14, alignment: .trailing)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                    .offset(y: y(hour * 60) - 12)
                }
                ForEach(agenda.today.filter { !$0.allDay }, id: \.self) { entry in
                    let top = y(entry.startMinute)
                    let height = max(y(entry.endMinute) - top, 34)
                    let past = entry.endMinute <= agenda.nowMinute
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(AgendaTint.color(entry.tint)).frame(width: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(HudTheme.mont(height > 70 ? 28 : 22, .black)).lineLimit(1)
                            if height > 70 {
                                Text("\(entry.time) \u{2013} \(entry.endTime)"
                                     + (entry.location.isEmpty ? "" : "  \u{00B7}  \(entry.location)"))
                                    .font(HudTheme.mont(18, .semibold)).lineLimit(1).foregroundStyle(HudTheme.inkDim)
                            }
                        }
                        .padding(.vertical, 6)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(past ? HudTheme.inkDim : HudTheme.ink)
                    .frame(width: geometry.size.width - gutter, height: height, alignment: .topLeading)
                    .background(Color.white.opacity(past ? 0.04 : 0.09), in: RoundedRectangle(cornerRadius: 10))
                    .offset(x: gutter, y: top)
                }
                if range.contains(agenda.nowMinute / 60) {
                    HStack(spacing: 0) {
                        Circle().fill(HudTheme.accent).frame(width: 14, height: 14)
                        Rectangle().fill(HudTheme.accent).frame(height: 3)
                    }
                    .frame(width: geometry.size.width - gutter + 7, height: 14)
                    .offset(x: gutter - 7, y: y(agenda.nowMinute) - 7)
                }
            }
        }
    }
}

/// The month: a week to a row, today marked, and the first few things on each day.
public struct CalendarMonthView: View {
    public var agenda: HudSnapshot.Agenda
    public init(_ agenda: HudSnapshot.Agenda) { self.agenda = agenda }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(agenda.monthTitle).font(HudTheme.mont(56, .black)).foregroundStyle(HudTheme.ink)
                Spacer()
                if let next = agenda.next {
                    Text("NEXT  ").font(HudTheme.mont(18, .black)).tracking(3).foregroundStyle(HudTheme.inkDim)
                    + Text("\(next.title.uppercased())  \u{00B7}  \(agenda.nextIn)")
                        .font(HudTheme.mont(18, .black)).foregroundStyle(HudTheme.accent)
                }
            }
            HStack(spacing: 10) {
                ForEach(agenda.weekdays, id: \.self) { day in
                    Text(day).font(HudTheme.mont(18, .black)).tracking(3).foregroundStyle(HudTheme.inkDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            let weeks = max(agenda.days.count / 7, 1)
            VStack(spacing: 10) {
                ForEach(0..<weeks, id: \.self) { week in
                    HStack(spacing: 10) {
                        ForEach(0..<7, id: \.self) { column in
                            let index = week * 7 + column
                            if agenda.days.indices.contains(index) { cell(agenda.days[index]) }
                        }
                    }
                }
            }
        }
        .padding(48)
        .appSurface()
    }

    private func cell(_ day: HudSnapshot.Agenda.Day) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(day.number)")
                .font(HudTheme.mont(26, .black))
                .foregroundStyle(day.isToday ? Color.black : day.inMonth ? HudTheme.ink : HudTheme.inkFaint)
                .frame(width: 46, height: 40)
                .background(day.isToday ? HudTheme.accent : .clear, in: Capsule())
            ForEach(day.titles, id: \.self) { title in
                Text(title).font(HudTheme.mont(17, .semibold)).lineLimit(1)
                    .foregroundStyle(day.inMonth ? HudTheme.ink.opacity(0.85) : HudTheme.inkFaint)
            }
            if day.more > 0 {
                Text("+\(day.more)").font(HudTheme.mont(16, .black)).foregroundStyle(HudTheme.inkDim)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(day.inMonth ? 0.05 : 0.02), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(day.isToday ? HudTheme.accent.opacity(0.6) : .clear, lineWidth: 2))
    }
}

// MARK: - Photos

/// Where the gallery's photos are, for drawing and for clicks.
public enum PhotosLayout {
    public static let columns = 6
    public static let rows = 3
    static let inset: CGFloat = 56
    static let top: CGFloat = 120
    static let gap: CGFloat = 16

    public static func tile(slot: Int, in size: CGSize) -> CGRect {
        let width = (size.width - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (size.height - top - inset - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return CGRect(x: inset + CGFloat(slot % columns) * (width + gap),
                      y: top + CGFloat(slot / columns) * (height + gap), width: width, height: height)
    }

    /// The photo under a point of the gallery, as an index into the library.
    public static func photo(at point: CGPoint, in size: CGSize, _ photos: HudSnapshot.Photos) -> Int? {
        for slot in 0..<(columns * rows) where tile(slot: slot, in: size).contains(point) {
            let index = photos.scrollRow * columns + slot
            return index < photos.count ? index : nil
        }
        return nil
    }

    public static func maxRow(_ count: Int) -> Int { max(0, (count + columns - 1) / columns - rows) }

    /// The row to show so that a photo is on screen.
    public static func row(showing index: Int, from row: Int) -> Int {
        let r = index / columns
        if r < row { return r }
        if r >= row + rows { return r - rows + 1 }
        return row
    }
}

/// A photo, or where one will be.
struct PhotoTile: View {
    var image: Image?
    var fill = true
    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image {
                if fill {
                    image.resizable().scaledToFill()
                } else {
                    image.resizable().scaledToFit()
                }
            } else {
                Image(systemName: "photo").font(.system(size: 34, weight: .light)).foregroundStyle(HudTheme.inkFaint)
            }
        }
        .clipped()
    }
}

public struct PhotosWidget: View {
    public var photos: HudSnapshot.Photos
    public var image: Image?
    public init(_ photos: HudSnapshot.Photos, image: Image?) {
        self.photos = photos
        self.image = image
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoTile(image: image)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            Text(photos.hasAccess ? (photos.count == 0 ? "NO PHOTOS" : photos.caption) : "ALLOW PHOTOS IN SETTINGS")
                .font(HudTheme.mont(16, .black)).tracking(2.5).lineLimit(1)
                .foregroundStyle(HudTheme.ink).padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
            .strokeBorder(HudTheme.edge, lineWidth: 1))
    }
}

/// One photo, large, with when (and where) it was taken.
public struct PhotoView: View {
    public var photos: HudSnapshot.Photos
    public var image: Image?
    public init(_ photos: HudSnapshot.Photos, image: Image?) {
        self.photos = photos
        self.image = image
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhotoTile(image: image, fill: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Text(photos.caption).font(HudTheme.mont(22, .black)).tracking(2.5).lineLimit(1)
                    .foregroundStyle(HudTheme.ink)
                Spacer()
                if photos.count > 0 {
                    Text("\(photos.current + 1) / \(photos.count)").font(HudTheme.mont(20, .black))
                        .monospacedDigit().foregroundStyle(HudTheme.inkDim)
                }
            }
        }
        .padding(32)
        .appSurface()
    }
}

/// Fullscreen: a grid of the library, the picked one marked; opened, that one alone.
public struct PhotosGallery: View {
    public var photos: HudSnapshot.Photos
    public var images: [Int: Image]
    public var size: CGSize
    public var hover: CGPoint?
    public init(_ photos: HudSnapshot.Photos, images: [Int: Image], size: CGSize = CGSize(width: 1792, height: 952),
                hover: CGPoint? = nil) {
        self.photos = photos
        self.images = images
        self.size = size
        self.hover = hover
    }

    public var body: some View {
        if photos.viewing {
            var shown = photos
            shown.current = photos.selected
            return AnyView(PhotoView(shown, image: images[photos.selected]))
        }
        return AnyView(ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline) {
                WidgetLabel(text: "PHOTOS")
                Spacer()
                Text(photos.caption).font(HudTheme.mont(20, .black)).tracking(2.5).foregroundStyle(HudTheme.inkDim)
            }
            .at(CGRect(x: 56, y: 44, width: size.width - 112, height: 40))
            if !photos.hasAccess || photos.count == 0 {
                Text(photos.hasAccess ? "No photos on the phone" : "Allow Photos in Settings to see them here")
                    .font(HudTheme.mont(30, .semibold)).foregroundStyle(HudTheme.inkDim)
                    .at(CGRect(origin: .zero, size: size), alignment: .center)
            }
            ForEach(0..<(PhotosLayout.columns * PhotosLayout.rows), id: \.self) { slot in
                let index = photos.scrollRow * PhotosLayout.columns + slot
                if index < photos.count {
                    let frame = PhotosLayout.tile(slot: slot, in: size)
                    let picked = index == photos.selected
                    let hovered = hover.map(frame.contains) ?? false
                    PhotoTile(image: images[index])
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(picked ? HudTheme.accent : hovered ? Color.white.opacity(0.6) : .clear,
                                          lineWidth: picked ? 5 : 3))
                        .at(frame)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .appSurface())
    }
}

// MARK: - Teleprompter

/// The note, scrolling on its own at the phone's speed, with a mark at the reading line.
public struct PrompterView: View {
    public var text: String
    public var prompter: HudSnapshot.Prompter
    public var fontSize: CGFloat
    public var showsHeader: Bool
    @State private var textHeight: CGFloat = 0

    public init(text: String, prompter: HudSnapshot.Prompter, fontSize: CGFloat, showsHeader: Bool = true) {
        self.text = text
        self.prompter = prompter
        self.fontSize = fontSize
        self.showsHeader = showsHeader
    }

    public var body: some View {
        GeometryReader { geometry in
            let readingLine = geometry.size.height * 0.32
            TimelineView(.animation(paused: !prompter.isRunning)) { context in
                let offset = min(prompter.offset(at: context.date), max(textHeight, 0))
                ZStack(alignment: .topLeading) {
                    Text(text.isEmpty ? "Write in the note, and it scrolls here." : text)
                        .font(HudTheme.mont(fontSize, .semibold))
                        .lineSpacing(fontSize * 0.28)
                        .foregroundStyle(text.isEmpty ? HudTheme.inkFaint : HudTheme.ink)
                        .frame(width: geometry.size.width - 36, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                        .offset(x: 36, y: readingLine - offset)
                    // The reading line: the words to say are level with it.
                    Rectangle().fill(HudTheme.accent).frame(width: 8, height: fontSize * 1.1)
                        .offset(y: readingLine)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                             .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 24)
        .overlay(alignment: .topLeading) {
            if showsHeader {
                HStack {
                    WidgetLabel(text: "TELEPROMPTER", accent: prompter.isRunning)
                    Spacer()
                    Text(prompter.isRunning ? "SPEED \(prompter.step)" : "PAUSED \u{00B7} SPEED \(prompter.step)")
                        .font(HudTheme.mont(16, .black)).tracking(2).foregroundStyle(HudTheme.inkDim)
                }
                .padding(.horizontal, 40).padding(.top, 28)
            }
        }
        .appSurface()
    }
}

public struct PrompterWidget: View {
    public var text: String
    public var prompter: HudSnapshot.Prompter
    public init(text: String, prompter: HudSnapshot.Prompter) {
        self.text = text
        self.prompter = prompter
    }

    public var body: some View {
        PrompterView(text: text, prompter: prompter, fontSize: 30, showsHeader: false)
            .overlay(alignment: .topLeading) {
                WidgetLabel(text: "PROMPTER", accent: prompter.isRunning).padding(22)
            }
    }
}
