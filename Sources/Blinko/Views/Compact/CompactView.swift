import SwiftUI

/// Closed island: content lives in two "wings" either side of the physical notch.
struct CompactView: View {
    let vm: NotchViewModel

    var body: some View {
        let notch = vm.geometry.notchSize
        let wing = vm.wingWidth
        let content = vm.compact

        HStack(spacing: 0) {
            leading(content)
                .padding(.leading, 12)
                .frame(width: wing, height: notch.height, alignment: .leading)
            Color.clear.frame(width: vm.closedNotchWidth)
            trailing(content)
                .padding(.trailing, 12)
                .frame(width: wing, height: notch.height, alignment: .trailing)
        }
        .frame(height: notch.height)
        .id(content.key)
        .transition(.wingReveal)
    }

    @ViewBuilder
    private func leading(_ content: CompactContent) -> some View {
        switch content {
        case .idle:
            EmptyView()
        case .music, .activity(.nowPlayingChanged):
            CompactArtwork(size: vm.geometry.notchSize.height - 10)
        case .clock:
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        case .timer:
            let mode = TimerService.shared.mode
            Image(systemName: mode.isBreak ? "cup.and.saucer.fill" : (mode == .focus ? "brain.head.profile.fill" : "timer"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(mode.isBreak ? .green : .orange)
        case .activity(let a):
            ActivityLeading(activity: a)
        }
    }

    @ViewBuilder
    private func trailing(_ content: CompactContent) -> some View {
        switch content {
        case .idle:
            EmptyView()
        case .music, .activity(.nowPlayingChanged):
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
        case .activity(let a):
            ActivityTrailing(activity: a)
        }
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

private struct CompactTimer: View {
    var body: some View {
        let timer = TimerService.shared
        if let end = timer.endDate {
            Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(timer.mode.isBreak ? .green : .orange)
                .frame(width: 50, alignment: .trailing)
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
        case .bluetooth(let name, let kind, _):
            HStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
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
        case .bluetooth(_, _, let connected):
            Text(connected ? "Connected" : "Disconnected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(connected ? Color.secondaryText : .red.opacity(0.85))
                .fixedSize()
        case .shelf(let count):
            Text("\(count)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.cyan)
                .contentTransition(.numericText())
        case .timerFinished:
            Text("Done").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
        case .nowPlayingChanged:
            EmptyView()
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
