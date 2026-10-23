import SwiftUI

// Clock, agenda and weather widget pieces (moved from HomeView) plus their small / medium cards.

// MARK: - Agenda

struct AgendaView: View {
    /// nil = automatic: the forecast shows when there is no agenda to show.
    @State private var forecastPinned: Bool?

    var body: some View {
        let cal = CalendarService.shared
        let prefs = Preferences.shared
        let weather = prefs.weatherEnabled && WeatherService.shared.report != nil
        let agendaEmpty = !prefs.showCalendar || !cal.authorized || cal.items.isEmpty
        let showForecast = weather && (forecastPinned ?? agendaEmpty)

        VStack(alignment: .leading, spacing: 6) {
            if prefs.showClock {
                HStack(alignment: .top, spacing: 4) {
                    ClockWidget()
                    Spacer(minLength: 0)
                    if weather {
                        WeatherChip(active: showForecast) {
                            withAnimation(Motion.micro) { forecastPinned = !showForecast }
                        }
                    }
                }
                .padding(.top, 4)
                if !prefs.worldClocks.isEmpty { WorldClocksRow() }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(Date.now, format: .dateTime.weekday(.wide))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                    Text(Date.now, format: .dateTime.day())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                }
                .padding(.top, 8)
            }

            if showForecast {
                ForecastStrip()
                    .transition(.opacity)
            } else if !prefs.showCalendar {
                EmptyView()
            } else if !cal.authorized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("See your next events here.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                    PillButton(title: cal.denied ? "Open Settings" : "Allow Calendar", symbol: "calendar") {
                        if cal.denied {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        } else {
                            cal.requestAccess()
                        }
                    }
                }
            } else if cal.items.isEmpty {
                Text("No more events today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .padding(.top, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(cal.items.prefix(6)) { item in AgendaRow(item: item) }
                    }
                }
            }
        }
    }
}

/// Large clock + date. Redraws once a minute, and only while the island is open.
struct ClockWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 0) {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(Theme.shared.font(30).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                    .contentTransition(.numericText())
                    .animation(Motion.micro, value: ctx.date)
                HStack(spacing: 4) {
                    Text(ctx.date, format: .dateTime.weekday(.wide))
                        .foregroundStyle(Color.red.opacity(0.9))
                    Text(ctx.date, format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(Color.secondaryText)
                }
                .font(.system(size: 11.5, weight: .semibold))
            }
        }
    }
}

/// Up to three extra time zones: city, time and day offset. Once a minute, only while visible.
struct WorldClocksRow: View {
    var body: some View {
        let zones = Preferences.shared.worldClocks.compactMap(TimeZone.init(identifier:))
        TimelineView(.everyMinute) { ctx in
            HStack(alignment: .top, spacing: 0) {
                ForEach(zones, id: \.identifier) { zone in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(WorldClock.city(zone))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.tertiaryText)
                            .lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(WorldClock.time(ctx.date, in: zone))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            if let offset = WorldClock.dayOffset(ctx.date, in: zone) {
                                Text(offset)
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(Color.orange.opacity(0.9))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

enum WorldClock {
    /// "America/Los_Angeles" → "Los Angeles".
    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    static func time(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// "+1" / "−1" when the zone is on another calendar day than here.
    static func dayOffset(_ date: Date, in zone: TimeZone) -> String? {
        var there = Calendar.current
        there.timeZone = zone
        let a = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let b = there.dateComponents([.year, .month, .day], from: date)
        guard let da = Calendar.current.date(from: a), let db = Calendar.current.date(from: b) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: da, to: db).day ?? 0
        return days == 0 ? nil : (days > 0 ? "+\(days)" : "−\(-days)")
    }
}

// MARK: - Weather

/// Current conditions next to the clock; tapping flips the column to the hourly forecast.
struct WeatherChip: View {
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        if let report = WeatherService.shared.report {
            Button(action: action) {
                VStack(spacing: 1) {
                    Image(systemName: WeatherCode.symbol(report.code, isDay: report.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 15))
                        .frame(height: 18)
                    Text(Temperature.format(report.temperature))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.primaryText)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Color.fillHover : (hovering ? Color.fillSubtle : .clear)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.94))
            .onHover { hovering = $0 }
            .help(WeatherCode.description(report.code))
        }
    }
}

/// Next five hours: time, symbol, temperature.
struct ForecastStrip: View {
    var body: some View {
        let weather = WeatherService.shared
        if let report = weather.report {
            HStack(spacing: 0) {
                ForEach(weather.upcomingHours) { hour in
                    VStack(spacing: 2) {
                        Text(hour.date, format: .dateTime.hour())
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(Color.tertiaryText)
                            .lineLimit(1)
                            .fixedSize()
                        Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 11))
                            .frame(height: 13)
                        Text(Temperature.format(hour.temperature))
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.fillSubtle))
            .help("\(WeatherCode.description(report.code)) · H \(Temperature.format(report.high)) L \(Temperature.format(report.low))")
        }
    }
}

enum Temperature {
    /// Values arrive in the locale's unit already; just round and add a degree sign.
    static func format(_ value: Double) -> String { "\(Int(value.rounded()))°" }
}

struct AgendaRow: View {
    let item: AgendaItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            if item.isReminder {
                Circle().stroke(Color(nsColor: item.color), lineWidth: 1.5).frame(width: 8, height: 8)
            } else {
                Capsule().fill(Color(nsColor: item.color)).frame(width: 3, height: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
            }
            Spacer(minLength: 0)
            if let url = item.meetingURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 18)
                        .background(Capsule().fill(Color.green.opacity(0.85)))
                }
                .buttonStyle(PressableStyle())
                .help("Join meeting")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Color.fillSubtle : .clear))
        .onHover { hovering = $0 }
    }

    private var timeLabel: String {
        if item.isAllDay { return "All day" }
        let f = Date.FormatStyle.dateTime.hour().minute()
        if !Calendar.current.isDateInToday(item.start) { return "Tomorrow " + item.start.formatted(f) }
        return item.isReminder ? item.start.formatted(f) : "\(item.start.formatted(f)) – \(item.end.formatted(f))"
    }
}
