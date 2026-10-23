import SwiftUI

// The tour's pages. Illustrations are small SwiftUI drawings (the first page uses the real
// island views, like Settings → Appearance). They advance on a slow timer only while their page
// is on screen, and hold one still frame when reduced motion is on.

// MARK: - 1 · Meet the island

struct MeetStep: View {
    @State private var phase = 0
    private let phases: [(mode: ThemePreviewMode, tab: NotchTab, label: LocalizedStringKey)]

    init() {
        var phases: [(mode: ThemePreviewMode, tab: NotchTab, label: LocalizedStringKey)] = [
            (.hud, .home, "System HUD"),
            (.open, .home, "Home"),
            (.open, .shelf, "Shelf"),
            (.open, .timer, "Timers"),
        ]
        if NowPlayingService.shared.hasTrack { phases.insert((.music, .home, "Now Playing"), at: 0) }
        self.phases = phases
        // Reduced motion holds the most telling frame: the open island.
        _phase = State(initialValue: Motion.reduced ? (phases.firstIndex { $0.mode == .open } ?? 0) : 0)
    }

    var body: some View {
        let current = phases[phase]
        TourPage(title: "Meet Blinko",
                 message: "Your notch, alive. Music, volume and brightness, your calendar, files and timers live where the notch is — and fold away when you don't need them.") {
            VStack(spacing: 12) {
                ThemePreview(mode: current.mode, tab: current.tab, width: 600)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    ForEach(phases.indices, id: \.self) { i in
                        TourChip(title: phases[i].label, selected: i == phase) {
                            withAnimation(Motion.open) { phase = i }
                        }
                    }
                }
            }
        } extra: {
            EmptyView()
        }
        .cyclingPhase($phase, count: phases.count, every: 2.6)
    }
}

// MARK: - 2 · Opening it

struct OpenStep: View {
    /// method × (approaching, open): hover, swipe, shortcut.
    @State private var phase = Motion.reduced ? 1 : 0

    var body: some View {
        let method = phase / 2
        let open = phase % 2 == 1
        TourPage(title: "Open it your way",
                 message: "Hover over the notch, swipe down on it with two fingers, or press the shortcut from anywhere. Move the pointer away or swipe up and it closes.") {
            TourStage {
                MiniNotch(open: open, openSize: CGSize(width: 330, height: 104)) {
                    MiniIslandContent()
                }
                gestureHint(method: method, open: open)
            }
        } extra: {
            HStack(spacing: 10) {
                MethodCard(symbol: "cursorarrow.motionlines", title: "Hover", detail: "Rest the pointer on the notch.",
                           active: method == 0)
                MethodCard(symbol: "hand.draw.fill", title: "Swipe down", detail: "Two fingers on the trackpad, over the notch.",
                           active: method == 1)
                MethodCard(symbol: "keyboard", title: "Shortcut", detail: nil, keys: KeyCaps.island, active: method == 2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .cyclingPhase($phase, count: 6, every: 1.3)
    }

    @ViewBuilder
    private func gestureHint(method: Int, open: Bool) -> some View {
        switch method {
        case 0:
            Image(systemName: "cursorarrow")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .offset(x: open ? 30 : 120, y: open ? 20 : 120)
        case 1:
            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.85)).frame(width: 15, height: 15)
                        .overlay(alignment: .top) {
                            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                                .frame(width: 5, height: open ? 40 : 0)
                                .offset(y: -40)
                        }
                }
            }
            .offset(y: open ? 140 : 46)
            .opacity(open ? 0.35 : 1)
        default:
            KeyCaps(keys: KeyCaps.island)
                .scaleEffect(open ? 0.94 : 1)
                .offset(y: 160)
                .opacity(open ? 0.6 : 1)
        }
    }
}

private struct MethodCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    var keys: [String] = []
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? Theme.shared.accent : .secondary)
                .frame(height: 18)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                KeyCaps(keys: keys)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(TourCardBackground(highlighted: active))
        .animation(Motion.micro, value: active)
    }
}

// MARK: - 3 · Command bar

struct CommandBarStep: View {
    @State private var phase = 0

    private struct Example {
        let query: String
        let symbol: String
        let result: Text
        let kind: LocalizedStringKey
    }

    private let examples: [Example] = [
        Example(query: "(12 + 4) * 3^2", symbol: "function", result: Text(verbatim: "144"), kind: "Calculator"),
        Example(query: "10 km to mi", symbol: "ruler", result: Text(verbatim: "6.21 mi"), kind: "Units"),
        Example(query: "t 25m", symbol: "timer", result: Text("Start a 25-minute timer"), kind: "Timer"),
        Example(query: "saf", symbol: "safari", result: Text(verbatim: "Safari"), kind: "Apps"),
    ]

    var body: some View {
        let example = examples[phase]
        TourPage(title: "Everything, one shortcut away",
                 message: "Press the command bar shortcut in any app to calculate, convert units and currencies, open apps, run Shortcuts, find clipboard and shelf items, start a timer or search the web.") {
            TourStage {
                MiniNotch(open: true, openSize: CGSize(width: 380, height: 112)) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(verbatim: example.query)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .environment(\.layoutDirection, .leftToRight)
                            Rectangle().fill(Theme.shared.accent).frame(width: 1.5, height: 15)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                        HStack(spacing: 9) {
                            Image(systemName: example.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.shared.accent.opacity(0.85)))
                            example.result.font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(example.kind).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                            Text(verbatim: "↩").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 36)
                    .id(phase)
                    .transition(.opacity)
                }
                KeyCaps(keys: KeyCaps.commandBar).offset(y: 164)
            }
        } extra: {
            FlowChips(items: ["Calculator", "Units & currency", "Apps", "Shortcuts", "Clipboard", "Shelf", "Timers", "Web search"])
        }
        .cyclingPhase($phase, count: examples.count, every: 2.2)
    }
}

// MARK: - 4 · Shelf

struct ShelfStep: View {
    /// 0 files on the desktop, 1 dragged onto the notch, 2 shelf open.
    @State private var phase = Motion.reduced ? 2 : 0

    var body: some View {
        TourPage(title: "A shelf for your files",
                 message: "Drag files onto the notch to park them on the Shelf. Drag them out again into any app, or send them with AirDrop in one click.") {
            TourStage {
                MiniNotch(open: phase == 2, openSize: CGSize(width: 340, height: 108),
                          closedWidth: phase == 1 ? 172 : 132, outline: phase == 1) {
                    HStack(spacing: 10) {
                        ShelfTile(symbol: "doc.richtext.fill", tint: .blue, name: "Report.pdf")
                        ShelfTile(symbol: "photo.fill", tint: .orange, name: "Moodboard.png")
                        ShelfTile(symbol: "film.fill", tint: .purple, name: "Demo.mov")
                        Spacer(minLength: 0)
                        VStack(spacing: 4) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.white)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.blue.opacity(0.85)))
                            Text(verbatim: "AirDrop").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 34)
                }
                // The files being dragged.
                HStack(spacing: -10) {
                    fileIcon("doc.richtext.fill", .blue).rotationEffect(.degrees(-8))
                    fileIcon("photo.fill", .orange).rotationEffect(.degrees(6))
                }
                .scaleEffect(phase == 1 ? 0.7 : 1)
                .offset(y: phase == 0 ? 132 : 12)
                .opacity(phase == 2 ? 0 : 1)
            }
        } extra: {
            HStack(spacing: 18) {
                TourBullet(symbol: "arrow.down.to.line", text: "Drop on the notch")
                TourBullet(symbol: "hand.draw", text: "Drag out anywhere")
                TourBullet(symbol: "dot.radiowaves.left.and.right", text: "AirDrop in one click")
            }
        }
        .cyclingPhase($phase, count: 3, every: 1.6)
    }

    private func fileIcon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20))
            .foregroundStyle(.white)
            .frame(width: 44, height: 54)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

private struct ShelfTile: View {
    let symbol: String
    let tint: Color
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 40, height: 44)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            Text(verbatim: name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                .frame(width: 62)
        }
    }
}

// MARK: - 6 · Finale

struct FinaleStep: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var glow = false

    var body: some View {
        TourPage(title: "You're all set",
                 message: "Blinko is in your notch now. Two more things worth knowing:", stageHeight: 150) {
            ZStack {
                Circle()
                    .fill(Theme.shared.accent.opacity(0.35))
                    .frame(width: 120, height: 120)
                    .blur(radius: 36)
                    .scaleEffect(glow ? 1.08 : 0.92)
                AppIconView(size: 108)
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                guard !Motion.reduced else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatCount(3, autoreverses: true)) { glow = true }
            }
        } extra: {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    HighlightCard(symbol: "sparkles.rectangle.stack.fill", tint: .agentAccent, title: "Agent Hub",
                                  detail: "Watch Claude Code work from the notch and approve its requests without switching windows.") {
                        Button("Connect Claude Code…") { SettingsWindowController.shared.show(pane: .agents) }
                            .controlSize(.small)
                    }
                    HighlightCard(symbol: "video.fill", tint: .green, title: "Meeting Mode",
                                  detail: "In a Zoom, Teams, Meet, FaceTime or Slack call the island shows the call's length and your microphone. Mute or leave from there.") {
                        Text("Automatic · no permission").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Toggle("Launch Blinko at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.isEnabled = v }
                    Spacer()
                    Text("Replay this tour from Settings → About.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 12))
            }
        }
    }
}

private struct HighlightCard<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint.gradient))
                Text(title).font(.system(size: 13.5, weight: .semibold))
            }
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            accessory
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(TourCardBackground(highlighted: false))
    }
}

// MARK: - Shared pieces

/// A small desktop with a menu bar; the notch hangs from its top edge, centred.
struct TourStage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.22, green: 0.25, blue: 0.42), Color(red: 0.52, green: 0.36, blue: 0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.black.opacity(0.25)).frame(height: 24)
            content
        }
        .frame(width: 600, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .environment(\.layoutDirection, .leftToRight) // a picture of the physical notch: never mirrored
        .accessibilityHidden(true)
    }
}

/// A drawn island that grows from the notch into an open panel.
struct MiniNotch<Content: View>: View {
    let open: Bool
    let openSize: CGSize
    var closedWidth: CGFloat = 132
    var outline = false
    @ViewBuilder var content: Content

    var body: some View {
        let size = open ? openSize : CGSize(width: closedWidth, height: 24)
        let shape = NotchShape(topRadius: open ? 8 : 5, bottomRadius: open ? 20 : 9)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if open { content.transition(.opacity) }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .overlay(shape.stroke(Theme.shared.accent, lineWidth: outline ? 1.5 : 0))
        .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 14, y: 6)
        .animation(Motion.open, value: open)
        .animation(Motion.compact, value: closedWidth)
    }
}

/// Generic open-island content: tab pills, artwork and a scrubber.
private struct MiniIslandContent: View {
    var body: some View {
        let accent = Theme.shared.accent
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Capsule().fill(accent).frame(width: 22, height: 8)
                ForEach(0..<4, id: \.self) { _ in Capsule().fill(Color.white.opacity(0.2)).frame(width: 12, height: 8) }
            }
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(Color.white.opacity(0.8)).frame(width: 90, height: 6)
                    Capsule().fill(Color.white.opacity(0.35)).frame(width: 60, height: 5)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(width: 200, height: 3)
                        Capsule().fill(accent).frame(width: 84, height: 3)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TourCardBackground: View {
    let highlighted: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(highlighted ? 0.09 : 0.05))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(highlighted ? Theme.shared.accent.opacity(0.8) : Color.white.opacity(0.08),
                              lineWidth: highlighted ? 1.5 : 1))
    }
}

struct TourChip: View {
    let title: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(selected ? Theme.shared.accent.opacity(0.25) : Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(selected ? Theme.shared.accent : Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Motion.micro, value: selected)
    }
}

private struct TourBullet: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        Label {
            Text(text).lineLimit(1).minimumScaleFactor(0.85)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.shared.accent)
        }
        .font(.system(size: 12, weight: .medium))
    }
}

/// Static capability chips that wrap onto a second line when a translation is long.
private struct FlowChips: View {
    let items: [LocalizedStringKey]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                Text(items[i])
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
        .frame(maxWidth: 560)
    }
}

/// Minimal centred flow layout.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? 560, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - row.width / 2
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.indices + [i], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

extension View {
    /// Advances `phase` every `interval` seconds while the view is on screen, for two rounds
    /// (a tour left open doesn't keep animating). Under reduced motion nothing moves by itself;
    /// the page keeps its still frame.
    func cyclingPhase(_ phase: Binding<Int>, count: Int, every interval: Double) -> some View {
        task {
            guard !Motion.reduced, count > 1 else { return }
            for _ in 0..<(count * 2 - 1) {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                withAnimation(Motion.open) { phase.wrappedValue = (phase.wrappedValue + 1) % count }
            }
        }
    }
}
