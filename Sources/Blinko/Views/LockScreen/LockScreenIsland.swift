import SwiftUI

// The island while it sits on the lock screen: privacy-filtered closed content and a small
// music player as the only thing a tap can expand.

extension Metrics {
    /// Open island on the lock screen: just the player, below the notch.
    static func lockScreenOpenSize(notchHeight: CGFloat) -> CGSize {
        CGSize(width: 470, height: notchHeight + 112)
    }
}

extension TransientActivity {
    /// Activities that reveal nothing personal and may show over the lock screen. Hidden:
    /// shelf and download file names, network names, and custom alerts (agents, scripts).
    var isLockScreenSafe: Bool {
        switch self {
        case .volume, .brightness, .keyboardBacklight, .microphone, .capsLock, .focusSession, .power,
             .lowBattery, .bluetooth, .timerFinished, .nowPlayingChanged, .focusMode, .privacy, .mutedWarning:
            true
        case .shelf, .network, .downloadFinished, .custom:
            false
        }
    }
}

extension NotchViewModel {
    /// Closed-island content on the lock screen, in priority order: safe transient activities,
    /// (agents only if allowed), timers / Pomodoro, music, charging. Calendar, clipboard,
    /// shelf, notes, downloads and meetings never show here.
    var lockScreenCompact: CompactContent {
        let lock = LockScreenSettings.shared
        let prefs = Preferences.shared
        if let activity = ActivityCenter.shared.current, activity.isLockScreenSafe { return .activity(activity) }
        if lock.showAgents, prefs.agentCompact, AgentHubService.shared.hasActivity { return .agent }
        if lock.islandTimer, TimerService.shared.hasRunning { return .timer }
        if lock.islandMusic, prefs.musicActivity, NowPlayingService.shared.isPlaying { return .music }
        let battery = BatteryService.shared
        if lock.islandCharging, battery.hasBattery, battery.isPluggedIn {
            return .activity(.power(level: battery.level, charging: battery.isCharging, pluggedIn: true))
        }
        return .idle
    }

    /// A tap may only expand the music player, and only when there is a track.
    var lockScreenCanExpand: Bool {
        LockScreenSettings.shared.islandMusic && NowPlayingService.shared.hasTrack
    }
}

/// The expanded island on the lock screen: artwork, title, progress, previous / play / next.
/// Collapses by itself after 20 s without a press.
struct LockScreenPlayerView: View {
    let vm: NotchViewModel
    @State private var presses = 0

    var body: some View {
        let np = NowPlayingService.shared
        let accent = Preferences.shared.artworkTint && np.hasTrack ? Color(nsColor: np.accent) : Theme.shared.accent

        HStack(alignment: .center, spacing: 14) {
            ArtworkView(image: np.artwork, cornerRadius: 12)
                .frame(width: 80, height: 80)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(np.hasTrack ? np.title : String(localized: "Nothing Playing"))
                        .font(Theme.shared.font(14))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    IslandIconButton(symbol: "chevron.up", size: 10, plate: 22, tint: .tertiaryText, help: "Close") {
                        vm.close()
                    }
                }
                Text(np.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accent.opacity(0.9))
                    .lineLimit(1)

                LockScreenProgress(accent: accent)
                    .padding(.top, 8)

                HStack(spacing: 18) {
                    Spacer(minLength: 0)
                    IslandIconButton(symbol: "backward.fill", size: 14, plate: 30, help: "Previous") {
                        np.previous(); presses += 1
                    }
                    IslandIconButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 20, plate: 36) {
                        np.togglePlayPause(); presses += 1
                    }
                    IslandIconButton(symbol: "forward.fill", size: 14, plate: 30, help: "Next") {
                        np.next(); presses += 1
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.shared.openTopRadius + 16) // clear the top "ears"
        .padding(.top, vm.geometry.notchSize.height + 8)
        .padding(.bottom, 12)
        .task(id: presses) {
            try? await Task.sleep(for: .seconds(20))
            if !Task.isCancelled, vm.lockScreenMode { vm.close() }
        }
    }
}

/// Elapsed / total with a thin bar. Ticks once a second, only while the player is open.
struct LockScreenProgress: View {
    let accent: Color

    var body: some View {
        let np = NowPlayingService.shared
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = min(np.elapsed(at: context.date), max(np.duration, 0))
            HStack(spacing: 8) {
                Text(Format.time(elapsed))
                LevelBar(value: np.duration > 0 ? elapsed / np.duration : 0, tint: accent, height: 4)
                Text(Format.time(np.duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.tertiaryText)
        }
        .opacity(np.duration > 0 ? 1 : 0)
    }
}
