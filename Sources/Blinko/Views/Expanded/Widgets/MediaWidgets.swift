import SwiftUI

// Now Playing widget pieces: the large player (moved from HomeView) and the medium card.

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
                    .overlay(alignment: .bottom) { ArtworkSpectrum(cornerRadius: 16) }
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
