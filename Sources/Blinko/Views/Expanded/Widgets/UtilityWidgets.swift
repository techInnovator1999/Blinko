import SwiftUI

// Timers, System Stats, Battery, Agents, Notes, Shelf and Clipboard widgets. Each reads its
// service here, at the leaf; stats sampling runs only while a stats widget is on screen.

// MARK: - Timers & Focus

/// The Pomodoro session when one is active, else the countdown that ends first; quick
/// presets when nothing runs.
struct TimersWidget: View {
    let size: HomeWidgetSize

    var body: some View {
        let timer = TimerService.shared
        let busy = (timer.mode.isPomodoro && timer.isActive) || timer.featured != nil
        WidgetCard {
            switch size {
            case .small:
                VStack(spacing: 6) {
                    MiniTimerRing(diameter: 60)
                    if busy {
                        TimerRunControls(compact: true)
                    } else {
                        HStack(spacing: 4) {
                            MiniChip(seconds: 300, width: 44)
                            MiniChip(seconds: 1500, width: 44)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            case .medium:
                HStack(spacing: 10) {
                    MiniTimerRing(diameter: 84)
                    VStack(spacing: 5) {
                        if busy {
                            TimerRunControls(compact: false)
                        } else {
                            MiniChip(seconds: 300, width: 58)
                            MiniChip(seconds: 1500, width: 58)
                            FocusChip(width: 58)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            case .large:
                HStack(spacing: 14) {
                    MiniTimerRing(diameter: 88)
                    VStack(alignment: .leading, spacing: 6) {
                        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                            GridRow {
                                MiniChip(seconds: 60, width: 46)
                                MiniChip(seconds: 300, width: 46)
                                MiniChip(seconds: 600, width: 46)
                            }
                            GridRow {
                                MiniChip(seconds: 1500, width: 46)
                                MiniChip(seconds: 2700, width: 46)
                                MiniChip(seconds: 3600, width: 46)
                            }
                        }
                        .fixedSize()
                        if busy {
                            TimerRunControls(compact: true)
                        } else {
                            FocusChip(width: 148)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Ring + remaining time. Redraws once a second while something runs, and only on screen.
private struct MiniTimerRing: View {
    let diameter: CGFloat

    var body: some View {
        let timer = TimerService.shared
        let pomodoro = timer.mode.isPomodoro && timer.isActive
        let featured = timer.featured
        let running = pomodoro ? timer.isRunning : featured?.isRunning == true
        let tint: Color = pomodoro ? (timer.mode.isBreak ? .green : .orange) : Theme.shared.accent
        TimelineView(.periodic(from: .now, by: running ? 1 : 3600)) { ctx in
            let progress = pomodoro ? 1 - timer.progress(at: ctx.date) : featured.map { 1 - $0.progress(at: ctx.date) } ?? 0
            let remaining = pomodoro ? timer.remaining(at: ctx.date) : featured?.remaining(at: ctx.date) ?? 0
            let label = pomodoro ? timer.mode.title : (featured.map { $0.isPaused ? String(localized: "Paused") : $0.label } ?? String(localized: "Ready"))
            ZStack {
                RingProgress(value: progress, tint: tint, lineWidth: max(4, diameter * 0.07))
                VStack(spacing: 0) {
                    Text(Format.time(remaining.rounded(.up)))
                        .font(Theme.shared.font(diameter * 0.21).monospacedDigit())
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(label)
                        .font(.system(size: diameter < 70 ? 8.5 : 9.5, weight: .semibold))
                        .foregroundStyle(pomodoro ? tint : .tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, diameter * 0.14)
            }
            .frame(width: diameter, height: diameter)
        }
    }
}

/// Pause / resume and stop for whatever the ring shows.
private struct TimerRunControls: View {
    let compact: Bool

    var body: some View {
        let timer = TimerService.shared
        let pomodoro = timer.mode.isPomodoro && timer.isActive
        let featured = timer.featured
        let paused = pomodoro ? timer.isPaused : featured?.isPaused == true
        let layout = compact ? AnyLayout(HStackLayout(spacing: 4)) : AnyLayout(VStackLayout(spacing: 5))
        layout {
            IslandIconButton(symbol: paused ? "play.fill" : "pause.fill", size: 11, plate: 26,
                             help: paused ? "Resume" : "Pause") {
                if pomodoro {
                    paused ? timer.resume() : timer.pause()
                } else if let featured {
                    paused ? timer.resume(featured.id) : timer.pause(featured.id)
                }
            }
            .background(Circle().fill(Color.fillSubtle))
            IslandIconButton(symbol: "xmark", size: 10, plate: 26, tint: .secondaryText, help: "Stop") {
                withAnimation(Motion.micro) {
                    if pomodoro { timer.cancel() } else if let featured { timer.cancel(featured.id) }
                }
            }
            .background(Circle().fill(Color.fillSubtle))
        }
    }
}

/// Small preset that starts a countdown.
private struct MiniChip: View {
    let seconds: TimeInterval
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.micro) { TimerService.shared.start(seconds, label: Format.duration(seconds)) }
        } label: {
            Text(Format.shortDuration(seconds))
                .font(Theme.shared.font(11.5))
                .foregroundStyle(Color.primaryText)
                .frame(width: width, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Theme.shared.accent.opacity(0.35) : Color.fillHover))
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help("Start a \(Format.duration(seconds)) timer")
    }
}

private struct FocusChip: View {
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(Motion.micro) { TimerService.shared.startFocus() }
        } label: {
            Label("Focus", systemImage: "brain.head.profile")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: width, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(hovering ? 0.28 : 0.16)))
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help("Start a Pomodoro focus session")
    }
}

// MARK: - System stats

/// CPU and memory (Small) plus network (Medium). Samples once a second only while visible:
/// the same reference-counted sampler as the System tab.
struct StatsWidget: View {
    let size: HomeWidgetSize

    var body: some View {
        let stats = SystemStatsService.shared
        WidgetCard {
            VStack(alignment: .leading, spacing: size == .small ? 9 : 6) {
                StatLine(title: "CPU", value: "\(Int((stats.cpu * 100).rounded()))%", tint: .cyan) {
                    if size == .small {
                        LevelBar(value: stats.cpu, tint: .cyan, height: 4)
                    } else {
                        Sparkline(values: stats.cpuHistory, tint: .cyan).frame(height: 12)
                    }
                }
                StatLine(title: "Memory", value: "\(Int((stats.memoryFraction * 100).rounded()))%", tint: .purple) {
                    if size == .small {
                        LevelBar(value: stats.memoryFraction, tint: .purple, height: 4)
                    } else {
                        Sparkline(values: stats.memHistory, tint: .purple).frame(height: 12)
                    }
                }
                if size == .small {
                    Spacer(minLength: 0)
                    Text("↓ " + Format.rate(stats.downRate))
                        .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    StatLine(title: "Network", value: "↓ " + Format.rate(stats.downRate), tint: .green) {
                        Sparkline(values: stats.netHistory, tint: .green, normalize: true).frame(height: 12)
                    }
                }
            }
        }
        .onAppear { stats.beginObserving() }
        .onDisappear { stats.endObserving() }
    }
}

private struct StatLine<Graph: View>: View {
    let title: LocalizedStringKey
    let value: String
    let tint: Color
    @ViewBuilder let graph: Graph

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).textCase(.uppercase)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(value)
                    .font(Theme.shared.font(11.5).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            graph
        }
        .animation(Motion.micro, value: value)
    }
}

// MARK: - Battery

struct BatteryWidget: View {
    var body: some View {
        let b = BatteryService.shared
        WidgetCard {
            if b.hasBattery {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetCaption(title: "Battery", tint: b.isPluggedIn ? .green : .yellow)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(b.level)%")
                            .font(Theme.shared.font(24).monospacedDigit())
                            .foregroundStyle(Color.primaryText)
                        if b.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, 2)
                    Spacer(minLength: 0)
                    LevelBar(value: Double(b.level) / 100,
                             tint: b.isPluggedIn ? .green : (b.level <= 20 ? .red : .white), height: 5)
                    Text(Self.status(b))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 5)
                }
            } else {
                WidgetHint(symbol: "powerplug.fill", title: "Power adapter")
            }
        }
    }

    static func status(_ b: BatteryService) -> String {
        if b.isCharging { return String(localized: "Charging") }
        if let m = b.minutesRemaining, !b.isPluggedIn { return "\(m / 60)h \(m % 60)m" }
        if b.isPluggedIn { return String(localized: "Plugged in") }
        return b.isLowPowerMode ? String(localized: "Low Power") : String(localized: "On battery")
    }
}

// MARK: - Agents

/// Agent Hub at a glance: how many agents work, and anything waiting for approval. Clicking
/// opens the Agents tab.
struct AgentsWidget: View {
    let size: HomeWidgetSize
    let vm: NotchViewModel

    var body: some View {
        let hub = AgentHubService.shared
        WidgetCard {
            if !Preferences.shared.agentHubEnabled {
                WidgetHint(symbol: "sparkles.rectangle.stack", title: "Agent Hub is off", action: "Set Up…") {
                    WidgetActions.openSettings(.agents, vm: vm)
                }
            } else if size == .small {
                small(hub)
            } else {
                list(hub)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: WidgetMetrics.cardRadius, style: .continuous))
        .onTapGesture { if Preferences.shared.agentHubEnabled { withAnimation(Motion.micro) { vm.tab = .agents } } }
        .help("Open the Agents tab")
    }

    private func small(_ hub: AgentHubService) -> some View {
        let working = hub.sessions.filter { $0.state == .working }.count
        return VStack(alignment: .leading, spacing: 0) {
            WidgetCaption(title: "Agents", tint: .agentAccent)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(working)")
                    .font(Theme.shared.font(26).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                Text(working == 0 ? "idle" : "working")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(working == 0 ? Color.tertiaryText : .agentAccent)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
            if !hub.approvals.isEmpty {
                Label("\(hub.approvals.count) to approve", systemImage: "hand.raised.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(hub.sessions.isEmpty ? "No sessions" : "\(hub.sessions.count) sessions")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Color.tertiaryText)
                    .lineLimit(1)
            }
        }
    }

    private func list(_ hub: AgentHubService) -> some View {
        let detailed = size == .large
        let rows = Array(hub.sessions.prefix(detailed ? 2 : 3))
        return VStack(alignment: .leading, spacing: 4) {
            WidgetCaption(title: "Agents", tint: .agentAccent,
                          trailing: hub.approvals.isEmpty ? nil : String(localized: "\(hub.approvals.count) to approve"))
            if rows.isEmpty {
                Spacer(minLength: 0)
                Text("No active sessions")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                Text("Start Claude Code in a terminal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { session in
                    AgentMiniRow(session: session, detailed: detailed)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct AgentMiniRow: View {
    let session: AgentSession
    let detailed: Bool

    var body: some View {
        HStack(alignment: detailed ? .top : .center, spacing: 6) {
            ZStack {
                if session.state == .working {
                    AgentSpinner(tint: .agentAccent, lineWidth: 1.5)
                } else {
                    Circle().fill(session.state.tint)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 11, height: 11)
            .padding(.top, detailed ? 2 : 0)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(verbatim: session.project)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(session.state.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(session.state == .idle ? Color.tertiaryText : session.state.tint)
                        .lineLimit(1)
                        .fixedSize()
                }
                if detailed, let detail = session.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Notes

/// The Notes scratchpad (same text as the Notes tab). Typing makes the panel key and keeps
/// the island open, as on the tab.
struct NotesWidget: View {
    let vm: NotchViewModel

    var body: some View {
        Scratchpad(vm: vm)
            .onDisappear { NotesService.shared.flush() }
    }
}

// MARK: - Shelf

/// The latest files on the shelf: drag them out, double-click to open. The caption opens
/// the Shelf tab.
struct ShelfWidget: View {
    let size: HomeWidgetSize
    let vm: NotchViewModel

    var body: some View {
        let shelf = ShelfService.shared
        let limit = size == .small ? 4 : (size == .medium ? 3 : 5)
        let recent = Array(shelf.items.suffix(limit).reversed())
        WidgetCard {
            VStack(alignment: .leading, spacing: 6) {
                Button { withAnimation(Motion.micro) { vm.tab = .shelf } } label: {
                    WidgetCaption(title: "Shelf", tint: .blue, trailing: shelf.items.isEmpty ? nil : "\(shelf.items.count)")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open the Shelf tab")
                if recent.isEmpty {
                    WidgetHint(symbol: "tray.and.arrow.down", title: "Drop files on the notch")
                } else if size == .small {
                    Grid(horizontalSpacing: 8, verticalSpacing: 2) {
                        ForEach(0..<2, id: \.self) { row in
                            GridRow {
                                ForEach(recent.dropFirst(row * 2).prefix(2)) { item in
                                    ShelfMiniTile(item: item, iconSize: 28, showsName: false)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(recent) { item in ShelfMiniTile(item: item, iconSize: 38, showsName: true) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .onAppear { shelf.purgeExpired() }
    }
}

private struct ShelfMiniTile: View {
    let item: ShelfItem
    let iconSize: CGFloat
    let showsName: Bool
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        let shelf = ShelfService.shared
        VStack(spacing: 3) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: FileIcons.icon(for: item.url)).resizable()
                }
            }
            .frame(width: iconSize, height: iconSize)
            if showsName {
                Text(item.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: iconSize + 8)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.fillSubtle : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(item) }
        .gesture(DragGesture(minimumDistance: 4).onChanged { _ in
            ShelfDrag.begin(urls: [item.url], thumbnail: thumbnail)
        })
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.name)
        .task(id: item.url) {
            shelf.thumbnail(for: item.url, size: iconSize) { thumbnail = $0 }
        }
    }
}

// MARK: - Clipboard

/// The latest copied items; click one to copy it again.
struct ClipboardWidget: View {
    let size: HomeWidgetSize

    var body: some View {
        let clip = ClipboardService.shared
        WidgetCard {
            VStack(alignment: .leading, spacing: 4) {
                WidgetCaption(title: "Clipboard", tint: .indigo)
                if !Preferences.shared.clipboardHistory {
                    WidgetHint(symbol: "doc.on.clipboard", title: "History is off")
                } else if clip.items.isEmpty {
                    WidgetHint(symbol: "doc.on.clipboard", title: "Nothing copied yet")
                } else if size == .small, let item = clip.items.first {
                    ClipMiniPreview(item: item)
                } else {
                    ForEach(clip.items.prefix(3)) { item in
                        ClipMiniRow(item: item, showsSource: size == .large)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Click-to-copy with a brief "Copied" confirmation.
private struct CopyFeedback: ViewModifier {
    let item: ClipItem
    @State private var copied = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if copied {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.7))
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                ClipboardService.shared.copy(item)
                withAnimation(Motion.micro) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(Motion.micro) { copied = false } }
            }
            .help("Click to copy")
    }
}

private struct ClipMiniPreview: View {
    let item: ClipItem

    var body: some View {
        Group {
            switch item.content {
            case .image(let image):
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            default:
                Text(item.preview)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .modifier(CopyFeedback(item: item))
    }
}

private struct ClipMiniRow: View {
    let item: ClipItem
    let showsSource: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.tertiaryText)
                .frame(width: 12)
            Text(item.preview)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if showsSource {
                Text(item.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.fillHover : Color.white.opacity(0.04)))
        .onHover { hovering = $0 }
        .modifier(CopyFeedback(item: item))
    }

    private var symbol: String {
        switch item.content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc"
        }
    }
}
