import SwiftUI

// Clock, Calendar and Weather widgets at their own sizes. The "Clock & Agenda" widget of the
// Default layout is `AgendaView` (TimeWidgets.swift), unchanged from the fixed Home.

// MARK: - Clock

/// Clock at Small: time, weekday and date, and the first world clock. Once a minute, only
/// while visible.
struct ClockCard: View {
    var body: some View {
        let zone = Preferences.shared.worldClocks.first.flatMap(TimeZone.init(identifier:))
        WidgetCard {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(Theme.shared.font(24).monospacedDigit())
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(ctx.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .lineLimit(1)
                    Text(ctx.date, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let zone {
                        WorldClockLine(zone: zone, date: ctx.date, stacked: true)
                    }
                }
            }
        }
    }
}

/// Clock at Medium: the Home clock with world clocks listed underneath.
struct ClockColumn: View {
    var body: some View {
        let zones = Preferences.shared.worldClocks.compactMap(TimeZone.init(identifier:))
        VStack(alignment: .leading, spacing: 8) {
            ClockWidget()
            if !zones.isEmpty {
                TimelineView(.everyMinute) { ctx in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(zones, id: \.identifier) { zone in
                            WorldClockLine(zone: zone, date: ctx.date)
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

/// "Tokyo   7:55 PM +1" on one line, or city above time in a narrow card.
private struct WorldClockLine: View {
    let zone: TimeZone
    let date: Date
    var stacked = false

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 0) {
                city
                time
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                city
                Spacer(minLength: 2)
                time
            }
        }
    }

    private var city: some View {
        Text(WorldClock.city(zone))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.tertiaryText)
            .lineLimit(1)
    }

    private var time: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(WorldClock.time(date, in: zone))
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .fixedSize()
            if let offset = WorldClock.dayOffset(date, in: zone) {
                Text(offset)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.orange.opacity(0.9))
            }
        }
    }
}

// MARK: - Calendar

/// Today's events and reminders (no clock): date header, then the agenda rows.
struct AgendaListWidget: View {
    let size: HomeWidgetSize

    var body: some View {
        let cal = CalendarService.shared
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .foregroundStyle(Color.red.opacity(0.9))
                Text(Date.now, format: .dateTime.day().month(size == .large ? .wide : .abbreviated))
                    .foregroundStyle(Color.primaryText)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .padding(.top, 8)
            .padding(.horizontal, 4)

            if !cal.authorized {
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
                .padding(.horizontal, 4)
            } else if cal.items.isEmpty {
                Text("No more events today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .padding(.horizontal, 4)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(cal.items.prefix(8)) { item in AgendaRow(item: item) }
                    }
                    .padding(.bottom, 8)
                }
                // Rows that run past the island fade out instead of being cut.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                             .init(color: cal.items.count > 3 ? .clear : .black, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

// MARK: - Weather

/// Weather at Small (conditions) or Medium (conditions + the next five hours). Shows a
/// set-up hint while weather is off: placing the widget never turns location or fetching on.
struct WeatherWidget: View {
    let size: HomeWidgetSize
    let vm: NotchViewModel

    var body: some View {
        let weather = WeatherService.shared
        WidgetCard {
            if !Preferences.shared.weatherEnabled {
                WidgetHint(symbol: "cloud.sun", title: "Weather is off", action: "Set Up…") {
                    WidgetActions.openSettings(.modules, vm: vm)
                }
            } else if let report = weather.report {
                if size == .small {
                    small(report)
                } else {
                    medium(report)
                }
            } else {
                WidgetHint(symbol: "cloud", title: weather.failed ? "Weather unavailable" : "Loading weather…")
            }
        }
        .help(weather.report.map { WeatherCode.description($0.code) } ?? "")
    }

    private func small(_ report: WeatherService.Report) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: WeatherCode.symbol(report.code, isDay: report.isDay))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))
                .frame(height: 24)
            Text(Temperature.format(report.temperature))
                .font(Theme.shared.font(26).monospacedDigit())
                .foregroundStyle(Color.primaryText)
                .padding(.top, 2)
            Spacer(minLength: 0)
            Text(WeatherCode.description(report.code))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            highLow(report)
        }
    }

    private func medium(_ report: WeatherService.Report) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: WeatherCode.symbol(report.code, isDay: report.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20))
                Text(Temperature.format(report.temperature))
                    .font(Theme.shared.font(22).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.place.isEmpty ? WeatherCode.description(report.code) : report.place)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                    Text("\(Temperature.format(report.high)) / \(Temperature.format(report.low))")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.tertiaryText)
                        .lineLimit(1)
                        .fixedSize()
                }
                .help("High \(Temperature.format(report.high)), low \(Temperature.format(report.low))")
                Spacer(minLength: 0)
            }
            Spacer(minLength: 4)
            ForecastStrip()
        }
    }

    private func highLow(_ report: WeatherService.Report) -> some View {
        Text("H \(Temperature.format(report.high))  L \(Temperature.format(report.low))")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.tertiaryText)
            .lineLimit(1)
    }
}
