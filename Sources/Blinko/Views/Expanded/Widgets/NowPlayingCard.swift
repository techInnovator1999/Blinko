import SwiftUI

// MARK: - Now Playing, Medium

/// Now Playing at Medium: artwork, title, a thin progress line and the three transport
/// buttons. During a call (Meeting mode) the meeting takes the slot, as on the large player.
struct NowPlayingCard: View {
    var body: some View {
        if Preferences.shared.meetingMode, MeetingService.shared.isInCall {
            MeetingMiniCard()
                .transition(.opacity.combined(with: .offset(y: 6)))
        } else {
            NowPlayingMini()
        }
    }
}

private struct NowPlayingMini: View {
    var body: some View {
        let np = NowPlayingService.shared
        let accent = Preferences.shared.artworkTint && np.hasTrack ? Color(nsColor: np.accent) : Theme.shared.accent
        WidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ArtworkView(image: np.artwork, cornerRadius: 8)
                        .frame(width: 38, height: 38)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .onTapGesture { np.openSourceApp() }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(np.hasTrack ? np.title : String(localized: "Nothing Playing"))
                            .font(Theme.shared.font(12.5))
                            .foregroundStyle(Color.primaryText)
                            .lineLimit(1)
                        Text(np.hasTrack ? np.artist : String(localized: "Play something"))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(accent.opacity(np.hasTrack ? 0.9 : 0.5))
                            .lineLimit(1)
                    }
                }
                MiniProgress(accent: accent)
                    .padding(.top, 8)
                    .opacity(np.hasTrack ? 1 : 0.35)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    IslandIconButton(symbol: "backward.fill", size: 12, plate: 26, help: "Previous") { np.previous() }
                    Spacer(minLength: 0)
                    IslandIconButton(symbol: np.isPlaying ? "pause.fill" : "play.fill", size: 17, plate: 32) {
                        np.togglePlayPause()
                    }
                    Spacer(minLength: 0)
                    IslandIconButton(symbol: "forward.fill", size: 12, plate: 26, help: "Next") { np.next() }
                }
                .padding(.horizontal, 4)
                .disabled(!np.hasTrack)
            }
        }
    }
}

/// Thin progress line; redraws once a second, only while playing and on screen.
private struct MiniProgress: View {
    let accent: Color

    var body: some View {
        let np = NowPlayingService.shared
        TimelineView(.periodic(from: .now, by: np.isPlaying ? 1 : 3600)) { ctx in
            let fraction = np.duration > 0 ? min(max(np.elapsed(at: ctx.date) / np.duration, 0), 1) : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(accent).frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Meeting, Medium

/// The call at Medium: app, title, length, then Mute / Show / Leave.
private struct MeetingMiniCard: View {
    var body: some View {
        let meeting = MeetingService.shared
        if let call = meeting.call {
            WidgetCard {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        MeetingAppIcon(call: call, size: 30)
                            .onTapGesture { meeting.bringToFront() }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: MeetingService.currentEvent(in: CalendarService.shared.items)?.title ?? call.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.primaryText)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text(timerInterval: call.start...call.start.addingTimeInterval(86_400), countsDown: false)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.secondaryText)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        MiniRoundControl(symbol: meeting.micMuted ? "mic.slash.fill" : "mic.fill",
                                         fill: meeting.micMuted ? .red : Color.white.opacity(0.14),
                                         help: meeting.micMuted ? "Unmute" : "Mute") { meeting.toggleMute() }
                        MiniRoundControl(symbol: "macwindow", fill: Color.white.opacity(0.14),
                                         help: "Bring the call to the front") { meeting.bringToFront() }
                        Spacer(minLength: 0)
                        if call.app.leave != nil {
                            MiniRoundControl(symbol: "phone.down.fill", fill: .red,
                                             help: meeting.canLeave ? "Leave the call" : "Brings the call to the front (needs Accessibility to leave from here)") {
                                meeting.leave()
                            }
                        }
                    }
                }
            }
            .animation(Motion.micro, value: meeting.isMuted)
        }
    }
}

private struct MiniRoundControl: View {
    let symbol: String
    let fill: Color
    var help: LocalizedStringKey = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .background(Circle().fill(fill))
                .overlay(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help(help)
    }
}
