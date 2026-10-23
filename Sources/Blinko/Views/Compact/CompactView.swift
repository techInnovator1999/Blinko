import SwiftUI

/// Closed island: content lives in two "wings" either side of the physical notch.
struct CompactView: View {
    let vm: NotchViewModel

    var body: some View {
        let notch = vm.geometry.notchSize
        let wing = vm.wingWidth
        let content = vm.compact

        let privacyEdge = vm.showsPrivacyEdge

        HStack(spacing: 0) {
            leading(content)
                .padding(.leading, 12)
                .frame(width: wing, height: notch.height, alignment: .leading)
            Color.clear.frame(width: vm.closedNotchWidth)
            trailing(content)
                .padding(.trailing, privacyEdge ? 19 : 12)
                .frame(width: wing, height: notch.height, alignment: .trailing)
        }
        .frame(height: notch.height)
        .overlay(alignment: .trailing) {
            // Camera / mic stay visible at the wing's edge whatever else the island shows.
            if privacyEdge {
                PrivacyDots(compact: true).padding(.trailing, 8)
            }
        }
        .id(content.key)
        .transition(.wingReveal)
    }

    @ViewBuilder
    private func leading(_ content: CompactContent) -> some View {
        switch content {
        case .idle:
            EmptyView()
        case .music, .activity(.nowPlayingChanged):
            HStack(spacing: 8) {
                CompactArtwork(size: vm.geometry.notchSize.height - 10)
                if vm.showsCompactLyrics {
                    CompactVisualizer().frame(width: 14, height: 11)
                }
            }
        case .clock:
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        case .timer:
            let mode = TimerService.shared.soonest?.mode ?? .countdown
            Image(systemName: mode.isBreak ? "cup.and.saucer.fill" : (mode == .focus ? "brain.head.profile.fill" : "timer"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(mode.isBreak ? .green : .orange)
        case .download:
            CompactDownloadRing()
        case .privacy:
            PrivacySymbols()
        case .meeting:
            MeetingCompactLeading()
        case .activity(let a):
            ActivityLeading(activity: a)
        }
    }

    @ViewBuilder
    private func trailing(_ content: CompactContent) -> some View {
        switch content {
        case .idle:
            EmptyView()
        case .music:
            if Preferences.shared.compactLyrics {
                CompactLyrics(showing: vm.showsCompactLyrics)
            } else {
                CompactVisualizer().frame(width: 16, height: 12)
            }
        case .activity(.nowPlayingChanged):
            CompactVisualizer().frame(width: 16, height: 12)
        case .clock:
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize()
            }
        case .timer:
            CompactTimer()
        case .download:
            CompactDownloadLabel()
        case .privacy:
            PrivacyDots(compact: false)
        case .meeting:
            MeetingCompactTrailing()
        case .activity(let a):
            ActivityTrailing(activity: a)
        }
    }
}

// MARK: - Downloads

private struct CompactDownloadRing: View {
    var body: some View {
        let progress = DownloadsService.shared.active
        ZStack {
            if let fraction = progress?.fraction {
                RingProgress(value: fraction, tint: .blue, lineWidth: 2.5)
                    .animation(.linear(duration: 0.5), value: fraction)
            } else {
                IndeterminateRing(tint: .blue)
            }
            Image(systemName: "arrow.down")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 17, height: 17)
    }
}

/// Spinning arc for downloads of unknown size.
private struct IndeterminateRing: View {
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: 2.5)
            SpinnerArc(color: NSColor(tint), lineWidth: 2.5)
        }
    }
}

/// Rotating arc animated by the render server (CABasicAnimation): zero per-frame app work,
/// unlike a SwiftUI `repeatForever` animation which re-evaluates every frame.
private struct SpinnerArc: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat

    func makeNSView(context: Context) -> SpinnerArcView { SpinnerArcView(color: color, lineWidth: lineWidth) }
    func updateNSView(_ view: SpinnerArcView, context: Context) {}
}

final class SpinnerArcView: NSView {
    private let arc = CAShapeLayer()

    init(color: NSColor, lineWidth: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        arc.fillColor = nil
        arc.strokeColor = color.cgColor
        arc.lineWidth = lineWidth
        arc.lineCap = .round
        arc.strokeEnd = 0.3
        layer?.addSublayer(arc)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.frame = bounds
        let inset = arc.lineWidth / 2
        arc.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
        CATransaction.commit()
        if arc.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 1
            spin.repeatCount = .infinity
            spin.isRemovedOnCompletion = false
            arc.add(spin, forKey: "spin")
        }
    }
}

private struct CompactDownloadLabel: View {
    var body: some View {
        let downloads = DownloadsService.shared
        if let progress = downloads.active {
            HStack(spacing: 3) {
                Text(progress.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? Format.bytes(Double(progress.received)))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
                if downloads.activeCount > 1 {
                    CountBadge(count: downloads.activeCount - 1)
                }
            }
        }
    }
}

/// "+N" capsule for additional items (downloads, timers) behind the one shown.
struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("+\(count)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(.black)
            .padding(.horizontal, 4)
            .frame(height: 13)
            .background(Capsule().fill(Color.white.opacity(0.85)))
            .fixedSize()
    }
}

// MARK: - Privacy

/// Green dot = camera, orange dot = microphone (the system's colour language).
private struct PrivacyDots: View {
    let compact: Bool

    var body: some View {
        let privacy = PrivacyService.shared
        if Preferences.shared.privacyIndicators, privacy.anyInUse {
            // Stacked vertically at the wing edge so they never crowd the content.
            let layout = compact ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
            layout {
                if privacy.cameraInUse { dot(.green) }
                if privacy.micInUse { dot(.orange) }
            }
            .transition(.opacity)
        }
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color)
            .frame(width: compact ? 5 : 7, height: compact ? 5 : 7)
            .shadow(color: color.opacity(0.7), radius: 3)
    }
}

private struct PrivacySymbols: View {
    var body: some View {
        let privacy = PrivacyService.shared
        HStack(spacing: 3) {
            if privacy.cameraInUse {
                Image(systemName: "video.fill").foregroundStyle(.green)
            }
            if privacy.micInUse {
                Image(systemName: "mic.fill").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 10, weight: .bold))
        .fixedSize()
    }
}

private struct CompactArtwork: View {
    let size: CGFloat
    var body: some View {
        let np = NowPlayingService.shared
        ArtworkView(image: np.artwork, cornerRadius: 5)
            .frame(width: size, height: size)
            .onTapGesture { np.openSourceApp() }
    }
}

private struct CompactVisualizer: View {
    var body: some View {
        let np = NowPlayingService.shared
        let prefs = Preferences.shared
        let color = prefs.artworkTint ? np.accent : .white
        if prefs.showVisualizer {
            AudioVisualizer(isPlaying: np.isPlaying, color: color)
        } else {
            Image(systemName: np.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(nsColor: color))
        }
    }
}

/// Current lyric line in the music wing. Loads lyrics on track change while the closed
/// island shows music; until they arrive (or if there are none) the visualizer stays.
private struct CompactLyrics: View {
    let showing: Bool

    var body: some View {
        let np = NowPlayingService.shared
        let lyrics = LyricsService.shared
        let key = LyricsService.key(title: np.title, artist: np.artist)
        Group {
            if showing {
                TimelineView(LyricsSchedule(lines: lyrics.lines, player: np)) { ctx in
                    LyricText(index: lyrics.lineIndex(at: np.elapsed(at: ctx.date)), size: 11, alignment: .trailing)
                }
            } else {
                CompactVisualizer().frame(width: 16, height: 12)
            }
        }
        .task(id: key) {
            await lyrics.load(title: np.title, artist: np.artist, album: np.album, duration: np.duration)
        }
    }
}

private struct CompactTimer: View {
    var body: some View {
        let timer = TimerService.shared
        if let next = timer.soonest {
            HStack(spacing: 4) {
                Text(timerInterval: Date.now...max(next.end, .now), countsDown: true)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(next.mode.isBreak ? .green : .orange)
                    .frame(width: 50, alignment: .trailing)
                if timer.othersRunning > 0 {
                    CountBadge(count: timer.othersRunning)
                }
            }
        }
    }
}

// MARK: - Transient activities

private struct ActivityLeading: View {
    let activity: TransientActivity

    var body: some View {
        switch activity {
        case .volume(let level, let muted):
            Image(systemName: volumeSymbol(level: level, muted: muted))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20, alignment: .leading)
        case .brightness(let level):
            Image(systemName: level > 0.5 ? "sun.max.fill" : "sun.min.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.yellow)
                .contentTransition(.symbolEffect(.replace))
        case .keyboardBacklight(let level):
            Image(systemName: level > 0 ? "light.max" : "light.min")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        case .microphone(let level, let muted):
            Image(systemName: muted || level == 0 ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(muted ? .red : .white)
                .contentTransition(.symbolEffect(.replace))
        case .capsLock(let on):
            HStack(spacing: 5) {
                Image(systemName: on ? "capslock.fill" : "capslock")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? .green : .white)
                    .contentTransition(.symbolEffect(.replace))
                Text("Caps Lock").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).fixedSize()
            }
        case .focusSession(_, let isBreak):
            Image(systemName: isBreak ? "cup.and.saucer.fill" : "brain.head.profile.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isBreak ? .green : .orange)
                .symbolEffect(.bounce, value: activity)
        case .power(_, let charging, let plugged):
            HStack(spacing: 5) {
                Image(systemName: plugged ? "bolt.fill" : "powerplug")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(plugged ? .green : .white)
                    .symbolEffect(.bounce, value: plugged)
                Text(plugged ? (charging ? "Charging" : "Plugged In") : "On Battery")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
        case .lowBattery:
            HStack(spacing: 5) {
                Image(systemName: "battery.25percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
                Text("Low Battery").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).fixedSize()
            }
        case .bluetooth(let name, let kind, _, _):
            HStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
        case .focusMode(let on, let name, let symbol):
            HStack(spacing: 6) {
                Image(systemName: on ? (symbol ?? "moon.fill") : "moon")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(on ? Color.indigo : .secondaryText)
                    .symbolEffect(.bounce, value: on)
                ((on ? name.map { Text(verbatim: $0) } : nil) ?? Text("Focus"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        case .privacy(let sensor):
            HStack(spacing: 6) {
                Image(systemName: sensor.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(sensor == .camera ? .green : .orange)
                Text(sensor.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).fixedSize()
            }
        case .network(let event):
            HStack(spacing: 6) {
                Image(systemName: event.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.tint)
                    .symbolEffect(.bounce, value: activity)
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        case .downloadFinished(let name, _):
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, value: activity)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .shelf:
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.cyan)
                .symbolEffect(.bounce, value: activity)
        case .timerFinished:
            Image(systemName: "alarm.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, options: .repeat(3), value: activity)
        case .nowPlayingChanged:
            EmptyView()
        case .mutedWarning:
            MutedWarningLeading()
        }
    }

    private func volumeSymbol(level: Float, muted: Bool) -> String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

private struct ActivityTrailing: View {
    let activity: TransientActivity

    var body: some View {
        switch activity {
        case .volume(let level, let muted):
            LevelBar(value: muted ? 0 : Double(level), tint: .white, height: 5).frame(width: 64)
        case .brightness(let level):
            LevelBar(value: Double(level), tint: .yellow, height: 5).frame(width: 64)
        case .keyboardBacklight(let level):
            LevelBar(value: Double(level), tint: .white, height: 5).frame(width: 64)
        case .microphone(let level, let muted):
            LevelBar(value: muted ? 0 : Double(level), tint: muted ? .red : .white, height: 5).frame(width: 64)
        case .capsLock(let on):
            Text(on ? "On" : "Off")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? .green : Color.secondaryText)
                .contentTransition(.interpolate)
        case .focusSession(let title, let isBreak):
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isBreak ? .green : .orange)
                .lineLimit(1)
                .fixedSize()
        case .power(let level, _, let plugged):
            BatteryGlyph(level: level, charging: plugged)
        case .lowBattery(let level):
            BatteryGlyph(level: level, charging: false)
        case .bluetooth(_, _, let connected, let battery):
            if connected, let battery {
                HeadphoneBattery(battery: battery)
            } else {
                Text(connected ? "Connected" : "Disconnected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(connected ? Color.secondaryText : .red.opacity(0.85))
                    .fixedSize()
            }
        case .focusMode(let on, _, _):
            Text(on ? "On" : "Off")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.indigo : .secondaryText)
        case .privacy:
            HStack(spacing: 5) {
                Text("In Use").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondaryText).fixedSize()
                PrivacyDots(compact: false)
            }
        case .network(let event):
            Text(event.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        case .downloadFinished:
            HStack(spacing: 4) {
                Text("Add").font(.system(size: 11, weight: .semibold)).foregroundStyle(.blue)
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .fixedSize()
            .help("Add to Shelf")
        case .shelf(let count):
            Text("\(count)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.cyan)
                .contentTransition(.numericText())
        case .timerFinished:
            Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        case .nowPlayingChanged:
            EmptyView()
        case .mutedWarning:
            MutedWarningTrailing()
        }
    }
}

struct BatteryGlyph: View {
    let level: Int
    let charging: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(level)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: Double(level)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(fill)
                    .frame(width: max(2, 18 * CGFloat(level) / 100), height: 7)
                    .padding(.leading, 2)
            }
            .overlay(alignment: .trailing) {
                Capsule().fill(Color.white.opacity(0.45)).frame(width: 1.5, height: 4).offset(x: 2.5)
            }
        }
    }

    private var fill: Color {
        if charging { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .white
    }
}

/// L / R / case levels for AirPods-style headphones; a single gauge for one-piece headsets.
private struct HeadphoneBattery: View {
    let battery: DeviceBattery

    var body: some View {
        if battery.hasBuds {
            HStack(spacing: 6) {
                if let l = battery.left { level("L", l) }
                if let r = battery.right { level("R", r) }
                if let c = battery.caseLevel { level("", c, symbol: "airpodspro.chargingcase.wireless.fill") }
            }
            .fixedSize()
        } else if let single = battery.single ?? battery.caseLevel {
            BatteryGlyph(level: single, charging: false)
        }
    }

    private func level(_ label: String, _ value: Int, symbol: String? = nil) -> some View {
        HStack(spacing: 2) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            } else {
                Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(Color.secondaryText)
            }
            Text("\(value)").font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(value <= 20 ? Color.red : .white)
    }
}

extension NetworkEvent {
    var symbol: String {
        switch self {
        case .wifi(let connected, _): connected ? "wifi" : "wifi.slash"
        case .vpn(let on): on ? "lock.shield.fill" : "lock.open.fill"
        case .hotspot: "personalhotspot"
        }
    }

    var tint: Color {
        switch self {
        case .wifi(let connected, _): connected ? .blue : .red
        case .vpn(let on): on ? .green : .secondaryText
        case .hotspot: .green
        }
    }

    var title: String {
        switch self {
        case .wifi(let connected, let ssid): connected ? (ssid ?? String(localized: "Wi-Fi")) : String(localized: "Wi-Fi")
        case .vpn: String(localized: "VPN")
        case .hotspot(let name): name ?? String(localized: "Hotspot")
        }
    }

    var detail: String {
        switch self {
        case .wifi(let connected, _), .vpn(let connected):
            connected ? String(localized: "Connected") : String(localized: "Disconnected")
        case .hotspot: String(localized: "Hotspot")
        }
    }
}
