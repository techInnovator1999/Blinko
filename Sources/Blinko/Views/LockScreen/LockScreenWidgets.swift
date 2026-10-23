import SwiftUI

/// The lock-screen widget row: now playing, battery, next event, active timer. Each card
/// shows only when it has something to say; each reads only its own service.
struct LockScreenWidgetsView: View {
    var body: some View {
        let lock = LockScreenSettings.shared
        HStack(alignment: .center, spacing: 12) {
            if lock.widgetMusic, NowPlayingService.shared.hasTrack { LockMusicCard() }
            if lock.widgetBattery, BatteryService.shared.hasBattery { LockBatteryCard() }
            if lock.widgetCalendar, Preferences.shared.showCalendar, LockNextEvent.current != nil {
                LockCalendarCard(details: lock.calendarDetails)
            }
            if lock.widgetTimer, TimerService.shared.soonest != nil || TimerService.shared.isPaused { LockTimerCard() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .animation(Motion.content, value: NowPlayingService.shared.hasTrack)
    }

    static let cardHeight: CGFloat = 104
}

/// Frosted, softly outlined card in the lock screen's own idiom.
private struct LockCard<Content: View>: View {
    var width: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        content
            .padding(14)
            .frame(width: width, height: LockScreenWidgetsView.cardHeight)
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.28))
            }
            .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .clipShape(shape)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct LockMusicCard: View {
    var body: some View {
        let np = NowPlayingService.shared
        LockCard(width: 310) {
            HStack(spacing: 12) {
                ArtworkView(image: np.artwork, cornerRadius: 12)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(np.title)
                        .font(Theme.shared.font(14))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                    Text(np.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    HStack(spacing: 10) {
                        IslandIconButton(symbol: "backward.fill", size: 13, plate: 30, help: "Previous") { np.previous() }
                        IslandIconButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 18, plate: 34) {
                            np.togglePlayPause()
                        }
                        IslandIconButton(symbol: "forward.fill", size: 13, plate: 30, help: "Next") { np.next() }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LockBatteryCard: View {
    var body: some View {
        let battery = BatteryService.shared
        let tint: Color = battery.isCharging || battery.isPluggedIn ? .green
            : battery.level <= 10 ? .red : battery.level <= 20 ? .orange : .white
        LockCard(width: 110) {
            VStack(spacing: 6) {
                ZStack {
                    RingProgress(value: Double(battery.level) / 100, tint: tint, lineWidth: 4)
                    Image(systemName: battery.isPluggedIn ? "bolt.fill" : "battery.100")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 44, height: 44)
                Text("\(battery.level)%")
                    .font(Theme.shared.font(14).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                    .contentTransition(.numericText(value: Double(battery.level)))
            }
        }
    }
}

/// The next agenda item that has not ended yet.
@MainActor
enum LockNextEvent {
    /// Snapshot rendering only.
    static var preview: AgendaItem?

    static var current: AgendaItem? {
        if let preview { return preview }
        let now = Date()
        return CalendarService.shared.items.first { $0.end > now && !$0.isAllDay }
            ?? CalendarService.shared.items.first { $0.end > now }
    }
}

/// Next event. Privacy: without "Show calendar details" only the time and a generic
/// "Event" / "Reminder" label appear — never the title.
private struct LockCalendarCard: View {
    let details: Bool

    var body: some View {
        LockCard(width: 210) {
            TimelineView(.everyMinute) { context in
                if let item = LockNextEvent.current {
                    HStack(alignment: .top, spacing: 10) {
                        Capsule().fill(Color(nsColor: item.color)).frame(width: 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.start <= context.date ? String(localized: "Now") : relative(item.start, from: context.date))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.secondaryText)
                            Text(details ? item.title
                                         : (item.isReminder ? String(localized: "Reminder") : String(localized: "Event")))
                                .font(Theme.shared.font(14))
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Text(item.isAllDay ? String(localized: "All day")
                                               : item.start.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.tertiaryText)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func relative(_ date: Date, from now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return String(localized: "In \(minutes) min") }
        if Calendar.current.isDate(date, inSameDayAs: now) { return String(localized: "Later today") }
        return String(localized: "Tomorrow")
    }
}

private struct LockTimerCard: View {
    var body: some View {
        let timer = TimerService.shared
        LockCard(width: 140) {
            VStack(alignment: .leading, spacing: 4) {
                if let next = timer.soonest {
                    Label(next.mode.isPomodoro ? next.mode.title : String(localized: "Timer"),
                          systemImage: next.mode.isBreak ? "cup.and.saucer.fill" : "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(next.mode.isBreak ? Color.green : Color.orange)
                    Spacer(minLength: 0)
                    Text(timerInterval: Date.now...max(next.end, .now), countsDown: true)
                        .font(Theme.shared.font(24).monospacedDigit())
                        .foregroundStyle(Color.primaryText)
                    if timer.othersRunning > 0 {
                        Text("+\(timer.othersRunning) more")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.tertiaryText)
                    }
                } else {
                    Label(String(localized: "Paused"), systemImage: "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                    Spacer(minLength: 0)
                    Text(Format.time(timer.remaining()))
                        .font(Theme.shared.font(24).monospacedDigit())
                        .foregroundStyle(Color.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
