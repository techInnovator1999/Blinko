import AVFoundation
import SwiftUI

struct HomeView: View {
    var body: some View {
        let prefs = Preferences.shared
        HStack(alignment: .top, spacing: 14) {
            HomePrimaryView() // media player, or the meeting card during a call
                .frame(maxWidth: .infinity, alignment: .leading)
            if prefs.showCalendar || prefs.showClock || prefs.weatherEnabled {
                Divider().overlay(Color.hairline).frame(height: 120).padding(.top, 8)
                AgendaView().frame(width: 176)
            }
            if prefs.showMirror {
                MirrorTile().frame(width: 112, height: 112).padding(.top, 8)
            }
        }
    }
}

// MARK: - Media

struct MediaPlayerView: View {
    var body: some View {
        let np = NowPlayingService.shared
        let accent = Preferences.shared.artworkTint && np.hasTrack ? Color(nsColor: np.accent) : Theme.shared.accent

        HStack(alignment: .center, spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                // Ambient glow from the artwork itself.
                ArtworkView(image: np.artwork, cornerRadius: 16)
                    .frame(width: 112, height: 112)
                    .background {
                        // Ambient glow: pre-blurred once per track. In a background so it never
                        // affects layout. 96px art + 2×28px padding → scale to match the cover.
                        if let glow = np.artworkGlow {
                            Image(nsImage: glow)
                                .resizable()
                                .frame(width: 112 * 152 / 96, height: 112 * 152 / 96)
                                .opacity(0.55)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay { if np.hasTrack { ArtworkSeekOverlay() } }
                    .scaleEffect(np.isPlaying || !np.hasTrack ? 1 : 0.9)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                if let icon = np.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 26, height: 26)
                        .offset(x: 6, y: 6)
                        .onTapGesture { np.openSourceApp() }
                        .help("Open source app")
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .padding(.top, 8)
            .animation(Motion.open, value: np.isPlaying)

            VStack(alignment: .leading, spacing: 0) {
                Text(np.hasTrack ? np.title : "Nothing Playing")
                    .font(Theme.shared.font(15))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                Text(np.hasTrack ? np.artist : "Play something to see it here")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(accent.opacity(np.hasTrack ? 0.9 : 0.5))
                    .lineLimit(1)
                    .padding(.top, 2)

                if Preferences.shared.showLyrics, np.hasTrack {
                    PlayerLyricLine()
                }

                Scrubber(accent: accent)
                    .padding(.top, LyricsService.shared.hasLyrics(for: LyricsService.key(title: np.title, artist: np.artist)) ? 7 : 12)
                    .opacity(np.hasTrack ? 1 : 0.35)
                    .disabled(!np.hasTrack)
                    .environment(\.layoutDirection, .leftToRight) // playback runs left to right in every language (HIG)

                HStack(spacing: 0) {
                    IslandIconButton(symbol: "shuffle", size: 11, plate: 26,
                                     tint: np.shuffle == .on ? accent : .tertiaryText, help: "Shuffle") {
                        np.toggleShuffle()
                    }
                    Spacer(minLength: 2)
                    IslandIconButton(symbol: "backward.fill", size: 15, plate: 32, help: "Previous") { np.previous() }
                    Spacer(minLength: 2)
                    IslandIconButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 22, plate: 40) {
                        np.togglePlayPause()
                    }
                    Spacer(minLength: 2)
                    IslandIconButton(symbol: "forward.fill", size: 15, plate: 32, help: "Next") { np.next() }
                    Spacer(minLength: 2)
                    IslandIconButton(symbol: np.repeatMode.symbol, size: 11, plate: 26,
                                     tint: np.repeatMode == .one || np.repeatMode == .all ? accent : .tertiaryText,
                                     help: "Repeat") {
                        np.cycleRepeat()
                    }
                }
                .padding(.top, 6)
                .environment(\.layoutDirection, .leftToRight) // transport controls are never mirrored (HIG)
            }
            .padding(.top, 8)
        }
    }
}

/// The current synced-lyrics line under the artist, cross-fading line to line. Loads on
/// track change while visible; redraws only at line boundaries (LyricsSchedule).
private struct PlayerLyricLine: View {
    var body: some View {
        let np = NowPlayingService.shared
        let lyrics = LyricsService.shared
        let key = LyricsService.key(title: np.title, artist: np.artist)
        ZStack(alignment: .leading) {
            if lyrics.hasLyrics(for: key) {
                TimelineView(LyricsSchedule(lines: lyrics.lines, player: np)) { ctx in
                    LyricText(index: lyrics.lineIndex(at: np.elapsed(at: ctx.date)), size: 11.5)
                }
                .padding(.top, 5)
                .transition(.opacity)
            }
        }
        .animation(Motion.content, value: lyrics.hasLyrics(for: key))
        .task(id: key) {
            await lyrics.load(title: np.title, artist: np.artist, album: np.album, duration: np.duration)
        }
    }
}

/// One lyric line; a new line slides up and fades in while the old one fades out.
struct LyricText: View {
    let index: Int?
    let size: CGFloat
    var alignment: Alignment = .leading

    var body: some View {
        let lines = LyricsService.shared.lines
        let text = index.flatMap { lines.indices.contains($0) ? lines[$0].text : nil } ?? ""
        ZStack(alignment: alignment) {
            Text(text.isEmpty ? "♪" : text)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
                .id(index ?? -1)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 5)),
                                        removal: .opacity.combined(with: .offset(y: -5))))
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .frame(height: size + 4)
        .clipped()
        .animation(Motion.content, value: index)
    }
}

/// Hovering the artwork reveals ±10 s seek zones; clicking the centre opens the source app.
private struct ArtworkSeekOverlay: View {
    @State private var hovering = false

    var body: some View {
        let np = NowPlayingService.shared
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(hovering ? 0.45 : 0))
            HStack(spacing: 0) {
                seekZone(symbol: "gobackward.10") { np.skip(by: -10) }
                seekZone(symbol: "goforward.10") { np.skip(by: 10) }
            }
            .opacity(hovering ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
    }

    private func seekZone(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
    }
}

private struct Scrubber: View {
    let accent: Color
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        let np = NowPlayingService.shared
        // Ticks once a second, and only while playing and on screen.
        TimelineView(.periodic(from: .now, by: np.isPlaying ? 1 : 3600)) { context in
            let elapsed = np.elapsed(at: context.date)
            let fraction = dragFraction ?? (np.duration > 0 ? elapsed / np.duration : 0)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(accent)
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                    .frame(height: hovering || dragFraction != nil ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in dragFraction = min(max(v.location.x / geo.size.width, 0), 1) }
                        .onEnded { _ in
                            if let f = dragFraction { np.seek(to: f * np.duration) }
                            dragFraction = nil
                        })
                }
                .frame(height: 10)
                .onHover { hovering = $0 }
                .animation(Motion.micro, value: hovering)

                HStack {
                    Text(Format.time(dragFraction.map { $0 * np.duration } ?? elapsed))
                    Spacer()
                    Text("-" + Format.time(max(0, np.duration - (dragFraction.map { $0 * np.duration } ?? elapsed))))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.tertiaryText)
            }
        }
    }
}

// MARK: - Agenda

private struct AgendaView: View {
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
private struct ClockWidget: View {
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
private struct WorldClocksRow: View {
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
private struct WeatherChip: View {
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
private struct ForecastStrip: View {
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

private struct AgendaRow: View {
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

// MARK: - Mirror

private struct MirrorTile: View {
    @State private var active = false
    @State private var hovering = false

    var body: some View {
        let camera = CameraService.shared
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.fillSubtle)
            if active, camera.status == .authorized {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: camera.status == .denied ? "video.slash.fill" : "camera.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text(camera.status == .denied ? "No Access" : "Mirror")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(hovering ? Color.primaryText : .secondaryText)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            withAnimation(Motion.content) { active.toggle() }
            active ? camera.start() : camera.stop()
        }
        .onDisappear {
            if active { camera.stop() }
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
