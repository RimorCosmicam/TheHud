import SwiftUI

// The panels held up alone. Each is the same data as its small panel, given the whole canvas:
// a Maps app with search and directions, the weather's forecast, and a clock with the day.

private extension View {
    /// Puts a view at a rect on the canvas.
    func placed(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .offset(x: rect.minX, y: rect.minY)
    }

    /// The floating card the Maps app's controls sit on.
    func mapCard(highlighted: Bool = false) -> some View {
        background(Color.black.opacity(highlighted ? 0.9 : 0.8),
                   in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(highlighted ? HudTheme.accent.opacity(0.7) : HudTheme.edge,
                              lineWidth: highlighted ? 2 : 1))
    }
}

// MARK: - Maps

public struct MapsApp: View {
    public var minimap: HudSnapshot.Minimap
    public var maps: HudSnapshot.Maps
    public var ground: Image?
    public var proceduralGround: Bool
    public var cursor: CGPoint?

    public init(minimap: HudSnapshot.Minimap, maps: HudSnapshot.Maps, ground: Image?,
                proceduralGround: Bool, cursor: CGPoint?) {
        self.minimap = minimap
        self.maps = maps
        self.ground = ground
        self.proceduralGround = proceduralGround
        self.cursor = cursor
    }

    private var layout: MapsLayout {
        MapsLayout(resultCount: maps.navigation == nil ? maps.results.count : 0,
                   navigating: maps.navigation != nil)
    }

    private var hover: MapsHitTarget { cursor.map(layout.hitTest) ?? .none }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            MinimapPanel(minimap, ground: ground, proceduralGround: proceduralGround,
                         showsHeader: false)
                .placed(layout.panel)

            if let navigation = maps.navigation {
                turnCard(navigation).placed(layout.turnFrame)
                tripCard(navigation).placed(layout.tripFrame)
            } else {
                searchField.placed(layout.searchFrame)
                results
            }

            zoomButton("plus", .zoomIn).placed(layout.zoomInFrame)
            zoomButton("minus", .zoomOut).placed(layout.zoomOutFrame)
            placeLabel
        }
        .frame(width: HudTheme.glassesSize.width, height: HudTheme.glassesSize.height,
               alignment: .topLeading)
    }

    private var searchField: some View {
        HStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(maps.isEditing ? HudTheme.accent : HudTheme.inkDim)
            if maps.query.isEmpty && !maps.isEditing {
                Text("Search Maps").font(HudTheme.mont(28, .semibold))
                    .foregroundStyle(HudTheme.inkDim)
            } else {
                HStack(spacing: 2) {
                    Text(maps.query).font(HudTheme.mont(28, .semibold))
                        .foregroundStyle(HudTheme.ink).lineLimit(1)
                    if maps.isEditing {
                        RoundedRectangle(cornerRadius: 1.5).fill(HudTheme.accent)
                            .frame(width: 3, height: 34)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxHeight: .infinity)
        .mapCard(highlighted: maps.isEditing || hover == .search)
    }

    @ViewBuilder
    private var results: some View {
        if let status = maps.status, maps.results.isEmpty {
            Text(status).font(HudTheme.mont(22, .black)).tracking(3)
                .foregroundStyle(HudTheme.inkDim)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .mapCard()
                .placed(layout.resultFrame(0))
        }
        ForEach(Array(maps.results.prefix(5).enumerated()), id: \.offset) { index, place in
            HStack(spacing: 18) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(index == 0 ? HudTheme.accent : HudTheme.inkDim)
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name).font(HudTheme.mont(26, .black)).lineLimit(1)
                        .foregroundStyle(HudTheme.ink)
                    Text(place.detail).font(HudTheme.mont(19, .semibold)).lineLimit(1)
                        .foregroundStyle(HudTheme.inkDim)
                }
                Spacer(minLength: 8)
                Text(place.distance).font(HudTheme.mont(22, .black)).tracking(1)
                    .foregroundStyle(HudTheme.inkDim)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .mapCard(highlighted: hover == .result(index))
            .padding(.vertical, 4)
            .placed(layout.resultFrame(index))
        }
    }

    private func turnCard(_ navigation: HudSnapshot.Maps.Navigation) -> some View {
        HStack(alignment: .center, spacing: 26) {
            Image(systemName: navigation.maneuver)
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 148, height: 148)
                .background(HudTheme.accent, in: RoundedRectangle(cornerRadius: 22,
                                                                   style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                if !navigation.arrived {
                    Text(navigation.stepDistance).font(HudTheme.mont(60, .black)).tracking(-1)
                        .foregroundStyle(HudTheme.ink)
                }
                Text(navigation.instruction).font(HudTheme.mont(27, .semibold))
                    .foregroundStyle(HudTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .mapCard()
    }

    private func tripCard(_ navigation: HudSnapshot.Maps.Navigation) -> some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(navigation.remainingTime).font(HudTheme.mont(40, .black))
                        .foregroundStyle(HudTheme.accent)
                    Text("\(navigation.remainingDistance)  \u{00B7}  ARRIVE \(navigation.arrival)")
                        .font(HudTheme.mont(22, .black)).tracking(1.5)
                        .foregroundStyle(HudTheme.ink)
                }
                Text(navigation.destination.uppercased())
                    .font(HudTheme.mont(18, .black)).tracking(2.5).lineLimit(1)
                    .foregroundStyle(HudTheme.inkDim)
            }
            .padding(.leading, 28)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mapCard()
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                tripButton(maps.driving ? "car.fill" : "figure.walk",
                           maps.driving ? "DRIVE" : "WALK", filled: false,
                           hovered: hover == .transport)
                    .offset(x: layout.transportFrame.minX - layout.tripFrame.minX,
                            y: layout.transportFrame.minY - layout.tripFrame.minY)
                tripButton("xmark", "END", filled: true, hovered: hover == .endRoute)
                    .offset(x: layout.endFrame.minX - layout.tripFrame.minX,
                            y: layout.endFrame.minY - layout.tripFrame.minY)
            }
        }
    }

    private func tripButton(_ symbol: String, _ label: String, filled: Bool,
                            hovered: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .bold))
            Text(label).font(HudTheme.mont(20, .black)).tracking(2)
        }
        .foregroundStyle(filled ? Color.black : HudTheme.ink)
        .frame(width: MapsLayout.tripButtonWidth, height: layout.endFrame.height)
        .background(filled ? HudTheme.accent.opacity(hovered ? 1 : 0.85)
                    : Color.white.opacity(hovered ? 0.2 : 0.1),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func zoomButton(_ symbol: String, _ target: MapsHitTarget) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(HudTheme.ink)
            .frame(width: MapsLayout.buttonSize, height: MapsLayout.buttonSize)
            .mapCard(highlighted: hover == target)
    }

    private var placeLabel: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(minimap.place).font(HudTheme.mont(24, .black)).tracking(3)
                .foregroundStyle(HudTheme.ink)
            Text(minimap.speed).font(HudTheme.mont(18, .black)).tracking(2)
                .foregroundStyle(HudTheme.inkDim)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .mapCard()
        .fixedSize()
        .frame(width: 600, alignment: .topTrailing)
        .offset(x: layout.panel.maxX - MapsLayout.margin - 600,
                y: layout.panel.minY + MapsLayout.margin)
    }
}

// MARK: - Weather

public struct WeatherApp: View {
    public var weather: HudSnapshot.Weather?
    public var size: CGSize
    public init(_ weather: HudSnapshot.Weather?, size: CGSize = fullAppSize) {
        self.weather = weather
        self.size = size
    }

    public var body: some View {
        Group {
            if let weather {
                HStack(alignment: .top, spacing: 56) {
                    VStack(alignment: .leading, spacing: 0) {
                        now(weather)
                        Spacer(minLength: 24)
                        details(weather)
                        if let air = weather.air {
                            Spacer(minLength: 20)
                            airRow(air)
                        }
                        Spacer(minLength: 24)
                        hourly(weather)
                    }
                    .frame(width: isWide(size) ? 900 : nil)
                    // In the centre there is room for today only.
                    if isWide(size) { week(weather) }
                }
            } else {
                Text("WAITING FOR THE WEATHER")
                    .hudLabel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HudTheme.surface,
                    in: RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: HudTheme.cornerRadius, style: .continuous)
            .strokeBorder(HudTheme.edge, lineWidth: 1))
    }

    private func now(_ weather: HudSnapshot.Weather) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(weather.place).hudLabel()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(weather.temperature)")
                        .font(HudTheme.mont(200, .black)).tracking(-8)
                    Text("\u{00B0}").font(HudTheme.mont(120, .black))
                }
                .foregroundStyle(HudTheme.ink)
                .padding(.top, 6)
                Text(weather.condition)
                    .font(HudTheme.mont(34, .black)).tracking(4)
                    .foregroundStyle(HudTheme.ink)
                Text("H \(weather.high)\u{00B0}    L \(weather.low)\u{00B0}")
                    .font(HudTheme.mont(26, .black)).tracking(3)
                    .foregroundStyle(HudTheme.inkDim)
                    .padding(.top, 10)
            }
            Spacer(minLength: 0)
            Image(systemName: weather.symbol)
                .font(.system(size: 170, weight: .thin))
                .foregroundStyle(HudTheme.ink)
                .padding(.top, 40)
        }
    }

    private func details(_ weather: HudSnapshot.Weather) -> some View {
        let items: [(String, String)] = [
            weather.feelsLike.map { ("FEELS LIKE", "\($0)\u{00B0}") },
            weather.humidity.map { ("HUMIDITY", "\($0)%") },
            weather.windKmh.map { ("WIND", "\($0) KM/H") },
            weather.sunrise.map { ("SUNRISE", $0) },
            weather.sunset.map { ("SUNSET", $0) },
        ].compactMap { $0 }
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(HudTheme.edge).frame(width: 1, height: 56)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.0).font(HudTheme.mont(15, .black)).tracking(2.5)
                        .foregroundStyle(HudTheme.inkDim)
                    Text(item.1).font(HudTheme.mont(30, .black))
                        .foregroundStyle(HudTheme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, index > 0 ? 22 : 0)
            }
        }
    }

    /// Air quality, UV and pollen: what to know before going out, beside the temperature.
    private func airRow(_ air: HudSnapshot.Weather.Air) -> some View {
        let items: [(String, String, String)] = [
            ("AIR", "\(air.index)", air.label),
            ("UV", String(format: "%.0f", air.uv), air.uvLabel),
            air.pm25.map { ("PM2.5", String(format: "%.0f", $0), "\u{00B5}G/M\u{00B3}") },
            air.pollen.map { ("POLLEN", "", $0) },
        ].compactMap { $0 }
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(HudTheme.edge).frame(width: 1, height: 56)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.0).font(HudTheme.mont(15, .black)).tracking(2.5)
                        .foregroundStyle(HudTheme.inkDim)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !item.1.isEmpty {
                            Text(item.1).font(HudTheme.mont(30, .black)).foregroundStyle(HudTheme.ink)
                        }
                        Text(item.2).font(HudTheme.mont(item.1.isEmpty ? 22 : 16, .black)).tracking(1.5)
                            .foregroundStyle(item.1.isEmpty ? HudTheme.ink : HudTheme.accent)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, index > 0 ? 22 : 0)
            }
        }
    }

    private func hourly(_ weather: HudSnapshot.Weather) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("NEXT HOURS").hudLabel()
            HStack(spacing: 0) {
                ForEach(Array(weather.hourly.prefix(12).enumerated()), id: \.offset) { _, hour in
                    VStack(spacing: 12) {
                        Text(hour.label).font(HudTheme.mont(18, .black)).tracking(1)
                            .foregroundStyle(HudTheme.inkDim)
                        Image(systemName: hour.symbol)
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(HudTheme.ink)
                            .frame(height: 36)
                        Text("\(hour.temperature)\u{00B0}").font(HudTheme.mont(28, .black))
                            .foregroundStyle(HudTheme.ink)
                        Text(hour.precipitation >= 20 ? "\(hour.precipitation)%" : " ")
                            .font(HudTheme.mont(16, .black))
                            .foregroundStyle(HudTheme.accent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 20)
            .background(Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func week(_ weather: HudSnapshot.Weather) -> some View {
        let days = Array(weather.daily.prefix(7))
        let low = days.map(\.low).min() ?? 0
        let high = days.map(\.high).max() ?? 1
        let span = Double(max(high - low, 1))
        return VStack(alignment: .leading, spacing: 0) {
            Text("THIS WEEK").hudLabel().padding(.bottom, 14)
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                if index > 0 { Rectangle().fill(HudTheme.edge).frame(height: 1) }
                HStack(spacing: 18) {
                    Text(day.label).font(HudTheme.mont(24, .black)).tracking(1.5)
                        .foregroundStyle(HudTheme.ink)
                        .frame(width: 118, alignment: .leading)
                    Image(systemName: day.symbol)
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(HudTheme.ink)
                        .frame(width: 52)
                    Text(day.precipitation >= 20 ? "\(day.precipitation)%" : "")
                        .font(HudTheme.mont(17, .black))
                        .foregroundStyle(HudTheme.accent)
                        .frame(width: 58, alignment: .leading)
                    Text("\(day.low)\u{00B0}").font(HudTheme.mont(26, .black))
                        .foregroundStyle(HudTheme.inkDim)
                        .frame(width: 58, alignment: .trailing)
                    GeometryReader { geo in
                        let from = CGFloat(Double(day.low - low) / span) * geo.size.width
                        let to = CGFloat(Double(day.high - low) / span) * geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(colors: [Color.white.opacity(0.6),
                                                              HudTheme.accent],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(to - from, 8))
                                .offset(x: from)
                        }
                        .frame(height: 8)
                        .frame(maxHeight: .infinity)
                    }
                    Text("\(day.high)\u{00B0}").font(HudTheme.mont(26, .black))
                        .foregroundStyle(HudTheme.ink)
                        .frame(width: 58, alignment: .trailing)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Clock

/// Where the clock app's timer card is, in the app's own points: scroll on it to set it,
/// click to start or pause, right-click to reset.
public enum ClockAppLayout {
    public static let timerCard = CGRect(x: 824, y: 330, width: 440, height: 320)

    /// The timer card for an app of this size: in the centre, under the time, on the left.
    public static func timerCard(in size: CGSize) -> CGRect {
        isWide(size) ? timerCard : CGRect(x: 48, y: 300, width: (size.width - 120) / 2, height: 320)
    }
}

public struct ClockApp: View {
    public var clock: HudSnapshot.Clock
    public var timer: HudSnapshot.TimerReading
    public var hover: CGPoint?
    public var size: CGSize
    public init(_ clock: HudSnapshot.Clock, timer: HudSnapshot.TimerReading = .init(),
                hover: CGPoint? = nil, size: CGSize = fullAppSize) {
        self.clock = clock
        self.timer = timer
        self.hover = hover
        self.size = size
    }

    public var body: some View {
        let wide = isWide(size)
        let card = ClockAppLayout.timerCard(in: size)
        ZStack(alignment: .topLeading) {
            // In the centre the digits are the clock; the dial needs the whole canvas.
            if wide {
                ClockDial(clock: clock)
                    .at(CGRect(x: 60, y: 126, width: 700, height: 700))
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(clock.time).font(HudTheme.mont(wide ? 176 : 150, .black)).tracking(-6)
                        .foregroundStyle(HudTheme.ink)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(clock.seconds).font(HudTheme.mont(64, .black))
                            .foregroundStyle(HudTheme.accent)
                            .monospacedDigit()
                        if let meridiem = clock.meridiem {
                            Text(meridiem).font(HudTheme.mont(34, .black))
                                .foregroundStyle(HudTheme.inkDim)
                        }
                    }
                }
                .lineLimit(1)
                Text("\(clock.weekday)  \u{00B7}  \(clock.date)")
                    .font(HudTheme.mont(28, .black)).tracking(4)
                    .foregroundStyle(HudTheme.inkDim)
            }
            .at(wide ? CGRect(x: 824, y: 40, width: 916, height: 270)
                : CGRect(x: 48, y: 30, width: size.width - 96, height: 250))

            timerCard.at(card)
            agenda.at(CGRect(x: card.maxX + 36, y: card.minY + 10,
                             width: size.width - card.maxX - 36 - (wide ? 52 : 48), height: 310))
            worldClocks.at(CGRect(x: card.minX, y: 730, width: size.width - card.minX - (wide ? 52 : 48),
                                  height: 170))
        }
        .appSurface()
    }

    private var timerCard: some View {
        let hovered = hover.map(ClockAppLayout.timerCard(in: size).contains) ?? false
        let hint: String
        switch timer.state {
        case .idle: hint = "SCROLL TO SET \u{00B7} CLICK TO START"
        case .running: hint = "CLICK TO PAUSE"
        case .paused: hint = "CLICK TO GO ON \u{00B7} RIGHT-CLICK TO RESET"
        case .done: hint = "CLICK TO RUN AGAIN"
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(timer.state == .done ? "TIME'S UP" : (timer.isStopwatch ? "STOPWATCH" : "TIMER"))
                    .font(HudTheme.mont(18, .black)).tracking(3)
                    .foregroundStyle(timer.state == .idle ? HudTheme.inkDim : HudTheme.accent)
                Spacer()
                Image(systemName: timer.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(HudTheme.inkDim)
            }
            Spacer(minLength: 0)
            Text(timer.text).font(HudTheme.mont(110, .black)).tracking(-3).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .foregroundStyle(timer.state == .done ? HudTheme.accent : HudTheme.ink)
            Spacer(minLength: 0)
            if let progress = timer.progress {
                ProgressLine(progress: progress).frame(height: 6).padding(.bottom, 16)
            }
            Text(hint).font(HudTheme.mont(14, .black)).tracking(2)
                .foregroundStyle(HudTheme.inkFaint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(28)
        .background(Color.white.opacity(hovered ? 0.1 : 0.05),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(hovered ? HudTheme.accent.opacity(0.7) : HudTheme.edge,
                          lineWidth: hovered ? 2 : 1))
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("TODAY").hudLabel()
            if clock.agenda.isEmpty {
                Text("Nothing else today")
                    .font(HudTheme.mont(28, .semibold))
                    .foregroundStyle(HudTheme.inkDim)
            }
            ForEach(Array(clock.agenda.prefix(3).enumerated()), id: \.offset) { _, event in
                HStack(spacing: 18) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(event.isNow ? HudTheme.accent : Color.white.opacity(0.25))
                        .frame(width: 5, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(HudTheme.mont(28, .black)).lineLimit(1)
                            .foregroundStyle(HudTheme.ink)
                        Text(event.isNow ? "NOW \u{00B7} UNTIL \(event.end ?? "")"
                             : [event.time, event.end].compactMap { $0 }.joined(separator: " \u{2013} "))
                            .font(HudTheme.mont(18, .black)).tracking(2)
                            .foregroundStyle(event.isNow ? HudTheme.accent : HudTheme.inkDim)
                    }
                }
            }
        }
    }

    private var worldClocks: some View {
        HStack(spacing: 0) {
            ForEach(Array(clock.worldClocks.enumerated()), id: \.offset) { index, place in
                if index > 0 { Rectangle().fill(HudTheme.edge).frame(width: 1, height: 84) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: place.isDay ? "sun.max" : "moon")
                            .font(.system(size: 16, weight: .bold))
                        Text(place.city).font(HudTheme.mont(16, .black)).tracking(2.5)
                    }
                    .foregroundStyle(HudTheme.inkDim)
                    Text(place.time).font(HudTheme.mont(40, .black))
                        .foregroundStyle(HudTheme.ink)
                    Text(place.offset).font(HudTheme.mont(16, .black)).tracking(2)
                        .foregroundStyle(HudTheme.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, index > 0 ? 28 : 0)
            }
        }
    }
}

/// An analogue face: minute ticks, bold hours, and a mustard second hand.
public struct ClockDial: View {
    public var clock: HudSnapshot.Clock
    public init(clock: HudSnapshot.Clock) { self.clock = clock }

    public var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)

            context.stroke(Path(ellipseIn: CGRect(x: centre.x - radius + 1, y: centre.y - radius + 1,
                                                  width: radius * 2 - 2, height: radius * 2 - 2)),
                           with: .color(.white.opacity(0.12)), lineWidth: 2)

            for tick in 0..<60 {
                let hour = tick % 5 == 0
                let angle = Double(tick) / 60 * 2 * .pi
                let outer = radius - 22
                let inner = outer - (hour ? 40 : 14)
                var path = Path()
                path.move(to: point(centre, inner, angle))
                path.addLine(to: point(centre, outer, angle))
                context.stroke(path, with: .color(.white.opacity(hour ? 0.9 : 0.3)),
                               style: StrokeStyle(lineWidth: hour ? 7 : 2.5, lineCap: .round))
            }
            for (number, hour) in [("12", 0), ("3", 3), ("6", 6), ("9", 9)] {
                context.draw(Text(number).font(HudTheme.mont(46, .black))
                                .foregroundStyle(HudTheme.inkDim),
                             at: point(centre, radius - 112, Double(hour) / 12 * 2 * .pi))
            }

            hand(context, centre, length: radius * 0.52, width: 16,
                 angle: clock.hourHand / 12 * 2 * .pi, color: .white)
            hand(context, centre, length: radius * 0.76, width: 10,
                 angle: clock.minuteHand / 60 * 2 * .pi, color: .white)
            hand(context, centre, length: radius * 0.84, width: 4, tail: 56,
                 angle: clock.secondHand / 60 * 2 * .pi, color: HudTheme.accent)

            context.fill(Path(ellipseIn: CGRect(x: centre.x - 14, y: centre.y - 14,
                                                width: 28, height: 28)),
                         with: .color(HudTheme.accent))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 5,
                                                width: 10, height: 10)),
                         with: .color(.black))
        }
    }

    /// Clockwise from twelve.
    private func point(_ centre: CGPoint, _ distance: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: centre.x + distance * CGFloat(sin(angle)),
                y: centre.y - distance * CGFloat(cos(angle)))
    }

    private func hand(_ context: GraphicsContext, _ centre: CGPoint, length: CGFloat,
                      width: CGFloat, tail: CGFloat = 0, angle: Double, color: Color) {
        var path = Path()
        path.move(to: point(centre, -tail, angle))
        path.addLine(to: point(centre, length, angle))
        context.stroke(path, with: .color(.black.opacity(0.6)),
                       style: StrokeStyle(lineWidth: width + 6, lineCap: .round))
        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
