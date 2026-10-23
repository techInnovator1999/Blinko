import AVFoundation
import SwiftUI

struct HomeView: View {
    var body: some View {
        let prefs = Preferences.shared
        HStack(alignment: .top, spacing: 14) {
            MediaPlayerView()
                .frame(maxWidth: .infinity, alignment: .leading)
            if prefs.showCalendar || prefs.showClock {
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
        let accent = Preferences.shared.artworkTint ? Color(nsColor: np.accent) : .white

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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                Text(np.hasTrack ? np.artist : "Play something to see it here")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(accent.opacity(np.hasTrack ? 0.9 : 0.5))
                    .lineLimit(1)
                    .padding(.top, 2)

                Scrubber(accent: accent)
                    .padding(.top, 12)
                    .opacity(np.hasTrack ? 1 : 0.35)
                    .disabled(!np.hasTrack)

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
            }
            .padding(.top, 8)
        }
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
    var body: some View {
        let cal = CalendarService.shared
        let prefs = Preferences.shared
        VStack(alignment: .leading, spacing: 6) {
            if prefs.showClock {
                ClockWidget().padding(.top, 4)
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

            if !prefs.showCalendar {
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
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
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
