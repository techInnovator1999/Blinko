import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shelf

struct ShelfView: View {
    @State private var airDropTargeted = false

    var body: some View {
        let shelf = ShelfService.shared
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                    .foregroundStyle(Color.white.opacity(0.14))
                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 22, weight: .medium))
                        Text("Drop files here")
                            .font(.system(size: 12, weight: .semibold))
                        Text("They'll wait for you on the shelf")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.tertiaryText)
                    }
                    .foregroundStyle(Color.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(shelf.items) { item in ShelfTile(item: item) }
                        }
                        .padding(10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { DownloadSuggestion().padding(.bottom, 8) }

            VStack(spacing: 8) {
                DropActionTile(symbol: "airplayaudio", title: "AirDrop", tint: .blue,
                               targeted: $airDropTargeted) { urls in
                    ShelfService.shared.airDrop(urls)
                } tap: {
                    if !shelf.items.isEmpty { shelf.airDrop(shelf.selectedOrAll) }
                }
                if !shelf.items.isEmpty {
                    PillButton(title: "Clear", symbol: "xmark") { withAnimation(Motion.micro) { shelf.clear() } }
                }
            }
            .frame(width: 96)
        }
        .onAppear { shelf.purgeExpired() }
    }
}

/// Offers the most recent finished download (from the Downloads activity) for the shelf.
private struct DownloadSuggestion: View {
    var body: some View {
        let shelf = ShelfService.shared
        if let url = DownloadsService.shared.recent, !shelf.items.contains(where: { $0.url == url }) {
            Button {
                withAnimation(Motion.micro) {
                    shelf.add([url])
                    DownloadsService.shared.clearRecent()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                    Text(url.lastPathComponent)
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 220)
                    Text("Add").foregroundStyle(.blue)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color(white: 0.16)))
                .overlay(Capsule().stroke(Color.hairline))
            }
            .buttonStyle(PressableStyle(scale: 0.95))
            .help("Add the downloaded file to the shelf")
            .transition(.opacity.combined(with: .offset(y: 4)))
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        let shelf = ShelfService.shared
        let selected = shelf.selection.contains(item.id)
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(for: .data)).resizable()
                    }
                }
                .frame(width: 52, height: 52)
                if hovering {
                    Button { withAnimation(Motion.micro) { shelf.remove(item) } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.3))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 6, y: -6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Theme.shared.accent.opacity(0.3) : (hovering ? Color.fillSubtle : .clear)))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .onTapGesture(count: 2) { shelf.open(item) }
        .onTapGesture {
            if shelf.selection.contains(item.id) { shelf.selection.remove(item.id) } else { shelf.selection.insert(item.id) }
        }
        // AppKit drag session instead of .onDrag, which can only carry one file: dragging a
        // selected tile drags the whole selection.
        .gesture(DragGesture(minimumDistance: 4).onChanged { _ in
            ShelfDrag.begin(urls: shelf.dragURLs(for: item), thumbnail: thumbnail)
        })
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Show in Finder") { shelf.reveal(item) }
            Button("AirDrop") { shelf.airDrop([item.url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .task(id: item.url) {
            shelf.thumbnail(for: item.url, size: 52) { thumbnail = $0 }
        }
    }
}

/// Starts a multi-item file drag from the island. Called from a SwiftUI DragGesture: the
/// current event is the mouse-drag that AppKit needs to begin the session.
@MainActor
enum ShelfDrag {
    private static var active = false

    static func begin(urls: [URL], thumbnail: NSImage?) {
        guard !active, !urls.isEmpty, let event = NSApp.currentEvent,
              event.type == .leftMouseDragged || event.type == .leftMouseDown,
              let view = event.window?.contentView else { return }
        active = true
        let point = view.convert(event.locationInWindow, from: nil)
        let items = urls.enumerated().map { index, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let image = index == 0 ? (thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
                                   : NSWorkspace.shared.icon(forFile: url.path)
            let offset = CGFloat(min(index, 4)) * 5 // a small fanned stack
            item.setDraggingFrame(NSRect(x: point.x - 26 + offset, y: point.y - 26 - offset, width: 52, height: 52),
                                  contents: image)
            return item
        }
        let session = view.beginDraggingSession(with: items, event: event, source: ShelfDragSource.shared)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    fileprivate static func ended() { active = false }
}

private final class ShelfDragSource: NSObject, NSDraggingSource {
    static let shared = ShelfDragSource()

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic, .link] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MainActor.assumeIsolated { ShelfDrag.ended() }
    }
}

private struct DropActionTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let tint: Color
    @Binding var targeted: Bool
    let drop: ([URL]) -> Void
    let tap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(targeted ? .white : tint)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(tint.opacity(targeted ? 0.85 : 0.14)))
        .scaleEffect(targeted ? 1.04 : 1)
        .animation(Motion.peek, value: targeted)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadFileURLs(from: providers) { drop($0) }
            return true
        }
    }
}

// MARK: - Clipboard

struct ClipboardView: View {
    var body: some View {
        let clip = ClipboardService.shared
        if !Preferences.shared.clipboardHistory {
            EmptyState(symbol: "doc.on.clipboard", title: "Clipboard history is off",
                       subtitle: "Turn it on in Settings → Modules")
        } else if clip.items.isEmpty {
            EmptyState(symbol: "doc.on.clipboard", title: "Nothing copied yet",
                       subtitle: "Copy text, images or files — they'll show up here")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(clip.items) { item in ClipCard(item: item) }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct ClipCard: View {
    let item: ClipItem
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                (item.sourceApp.map { Text(verbatim: $0) } ?? Text("Copied"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(Color.tertiaryText)

            Group {
                switch item.content {
                case .image(let image):
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                default:
                    Text(item.preview)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(10)
        .frame(width: 150, height: 130)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(hovering ? Color.fillHover : Color.fillSubtle))
        .overlay {
            if copied {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.6))
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .onTapGesture {
            ClipboardService.shared.copy(item)
            withAnimation(Motion.micro) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(Motion.micro) { copied = false } }
        }
        .contextMenu {
            Button("Copy") { ClipboardService.shared.copy(item) }
            Button("Delete") { ClipboardService.shared.remove(item) }
            Divider()
            Button("Clear History") { ClipboardService.shared.clear() }
        }
    }

    private var icon: String {
        switch item.content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc"
        }
    }
}

// MARK: - System stats

struct StatsView: View {
    var body: some View {
        let stats = SystemStatsService.shared
        HStack(spacing: 10) {
            StatCard(title: "CPU", value: "\(Int((stats.cpu * 100).rounded()))%",
                     detail: String(localized: "\(ProcessInfo.processInfo.activeProcessorCount) cores"),
                     history: stats.cpuHistory, tint: .cyan, normalize: false)
            StatCard(title: "Memory", value: Format.bytes(stats.memoryUsed),
                     detail: String(localized: "of \(Format.bytes(stats.memoryTotal))", comment: "Memory: used of total"),
                     history: stats.memHistory, tint: .purple, normalize: false)
            StatCard(title: "Network", value: "↓ " + Format.rate(stats.downRate),
                     detail: "↑ " + Format.rate(stats.upRate),
                     history: stats.netHistory, tint: .green, normalize: true)
            BatteryCard()
        }
        .onAppear { stats.beginObserving() }
        .onDisappear { stats.endObserving() }
    }
}

private struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    let detail: String
    let history: [Double]
    let tint: Color
    let normalize: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).textCase(.uppercase)
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(value)
                .font(Theme.shared.font(15).monospacedDigit())
                .foregroundStyle(Color.primaryText)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.tertiaryText)
                .lineLimit(1)
            Sparkline(values: history, tint: tint, normalize: normalize)
                .padding(.top, 6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.fillSubtle))
        .animation(Motion.micro, value: value)
    }
}

private struct BatteryCard: View {
    var body: some View {
        let b = BatteryService.shared
        VStack(alignment: .leading, spacing: 2) {
            Text("BATTERY")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.yellow)
            if b.hasBattery {
                Text("\(b.level)%")
                    .font(Theme.shared.font(15).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                Text(status(b))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                LevelBar(value: Double(b.level) / 100, tint: b.isPluggedIn ? .green : (b.level <= 20 ? .red : .white), height: 6)
            } else {
                Text("Power adapter")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.fillSubtle))
    }

    private func status(_ b: BatteryService) -> String {
        var parts: [String] = []
        if b.isCharging { parts.append(String(localized: "Charging")) } else if b.isPluggedIn { parts.append(String(localized: "Plugged in")) }
        if let m = b.minutesRemaining { parts.append(String(localized: "\(m / 60)h \(m % 60)m", comment: "Battery time remaining: hours, minutes")) }
        if b.isLowPowerMode { parts.append(String(localized: "Low Power")) }
        return parts.isEmpty ? String(localized: "On battery") : parts.joined(separator: " · ")
    }
}

// MARK: - Timer

struct TimerView: View {
    enum Page: String, CaseIterable { case timer = "Timer", focus = "Focus" }
    @State private var page: Page = TimerService.shared.mode.isPomodoro ? .focus : .timer
    @Namespace private var pageNS

    var body: some View {
        let timer = TimerService.shared
        HStack(spacing: 18) {
            Group {
                switch page {
                case .timer: CountdownRing()
                case .focus: PomodoroRing(tint: timer.mode.isBreak ? .green : .orange)
                }
            }
            .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(Page.allCases, id: \.self) { p in
                        Button { withAnimation(Motion.micro) { page = p } } label: {
                            Text(LocalizedStringKey(p.rawValue))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(page == p ? Theme.shared.onAccent : .secondaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 22)
                                .background {
                                    if page == p { Capsule().fill(Theme.shared.accent).matchedGeometryEffect(id: "page", in: pageNS) }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
                .padding(2)
                .background(Capsule().fill(Color.white.opacity(0.05)))

                Group {
                    switch page {
                    case .timer: CountdownControls()
                    case .focus: FocusControls()
                    }
                }
                .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Big ring + remaining time. Ticks 4×/s only while something runs and the tab is visible.
private struct RingFace: View {
    let progress: Double
    let remaining: TimeInterval
    let status: String
    let tint: Color
    var statusTint: Color = .tertiaryText

    var body: some View {
        ZStack {
            RingProgress(value: progress, tint: tint, lineWidth: 6)
            VStack(spacing: 2) {
                Text(Format.time(remaining))
                    .font(Theme.shared.font(24).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                    .contentTransition(.numericText(countsDown: true))
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }
        }
        .animation(.linear(duration: 0.25), value: progress)
    }
}

private struct PomodoroRing: View {
    let tint: Color

    var body: some View {
        let timer = TimerService.shared
        TimelineView(.periodic(from: .now, by: timer.isRunning ? 0.25 : 3600)) { ctx in
            RingFace(progress: timer.isActive ? 1 - timer.progress(at: ctx.date) : 0,
                     remaining: timer.isActive ? timer.remaining(at: ctx.date).rounded(.up) : 0,
                     status: status(timer), tint: tint,
                     statusTint: timer.mode.isPomodoro ? tint : .tertiaryText)
        }
    }

    private func status(_ t: TimerService) -> String {
        guard t.mode.isPomodoro else { return String(localized: "Ready") }
        return t.isPaused ? String(localized: "\(t.mode.title) · Paused") : t.mode.title
    }
}

/// Follows the countdown that ends first (or the latest one when all are paused).
private struct CountdownRing: View {
    var body: some View {
        let featured = TimerService.shared.featured
        TimelineView(.periodic(from: .now, by: featured?.isRunning == true ? 0.25 : 3600)) { ctx in
            RingFace(progress: featured.map { 1 - $0.progress(at: ctx.date) } ?? 0,
                     remaining: featured?.remaining(at: ctx.date).rounded(.up) ?? 0,
                     status: featured.map { $0.isPaused ? String(localized: "Paused") : $0.label } ?? String(localized: "Ready"),
                     tint: Theme.shared.accent)
        }
    }
}

private struct CountdownControls: View {
    private let presets: [TimeInterval] = [60, 300, 600, 1500, 2700, 3600]

    var body: some View {
        let timer = TimerService.shared
        HStack(alignment: .top, spacing: 14) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(presets[(row * 3)..<(row * 3 + 3)], id: \.self) { seconds in
                            PresetChip(title: Format.shortDuration(seconds)) {
                                withAnimation(Motion.micro) { timer.start(seconds, label: Format.duration(seconds)) }
                            }
                        }
                    }
                }
            }
            .fixedSize()

            if timer.timers.isEmpty {
                Text("Start as many as you like — they run side by side.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .frame(width: 150, alignment: .leading)
                    .padding(.top, 6)
            } else if timer.timers.count <= 3 {
                rows(timer.timers).frame(maxWidth: 260)
            } else {
                ScrollView(.vertical, showsIndicators: false) { rows(timer.timers) }
                    .frame(maxWidth: 260, maxHeight: 108)
            }
        }
    }

    private func rows(_ timers: [CountdownTimer]) -> some View {
        VStack(spacing: 4) {
            ForEach(timers) { t in
                CountdownRow(timer: t)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct CountdownRow: View {
    let timer: CountdownTimer

    var body: some View {
        let service = TimerService.shared
        HStack(spacing: 6) {
            Circle()
                .fill(timer.isPaused ? Color.tertiaryText : Theme.shared.accent)
                .frame(width: 6, height: 6)
            Text(timer.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Group {
                if let end = timer.endDate {
                    Text(timerInterval: Date.now...max(end, .now), countsDown: true)
                } else {
                    Text(Format.time(timer.remaining().rounded(.up)))
                }
            }
            .font(Theme.shared.font(13).monospacedDigit())
            .foregroundStyle(timer.isPaused ? Color.tertiaryText : .primaryText)
            .multilineTextAlignment(.trailing)
            .frame(minWidth: 44, alignment: .trailing)
            IslandIconButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", size: 9, plate: 22,
                             help: timer.isPaused ? "Resume" : "Pause") {
                timer.isPaused ? service.resume(timer.id) : service.pause(timer.id)
            }
            IslandIconButton(symbol: "xmark", size: 9, plate: 22, tint: .secondaryText, help: "Cancel") {
                withAnimation(Motion.micro) { service.cancel(timer.id) }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.fillSubtle))
        .contextMenu {
            Button("Add 1 Minute") { service.add(60, to: timer.id) }
            Button("Cancel Timer") { service.cancel(timer.id) }
            Divider()
            Button("Cancel All Timers") { service.cancelAllCountdowns() }
        }
    }
}

private struct FocusControls: View {
    var body: some View {
        let timer = TimerService.shared
        let prefs = Preferences.shared
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < timer.completedFocusSessions % 4 || (timer.mode == .longBreak) ? Color.orange : Color.white.opacity(0.15))
                        .frame(width: 8, height: 8)
                }
                Text("\(prefs.focusMinutes)m focus · \(prefs.shortBreakMinutes)m break · \(prefs.longBreakMinutes)m long")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .padding(.leading, 4)
            }
            if timer.mode.isPomodoro {
                HStack(spacing: 8) {
                    RunControls()
                    PillButton(title: "Skip", symbol: "forward.end.fill") { timer.skipSession() }
                }
            } else {
                PillButton(title: "Start Focus", symbol: "play.fill", prominent: true) { timer.startFocus() }
            }
        }
        .animation(Motion.micro, value: timer.mode)
    }
}

private struct RunControls: View {
    var body: some View {
        let timer = TimerService.shared
        HStack(spacing: 8) {
            PillButton(title: timer.isPaused ? "Resume" : "Pause",
                       symbol: timer.isPaused ? "play.fill" : "pause.fill", prominent: true) {
                timer.isPaused ? timer.resume() : timer.pause()
            }
            PillButton(title: "Stop", symbol: "xmark") { timer.cancel() }
        }
    }
}

struct PresetChip: View {
    let title: String
    var compact = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.shared.font(compact ? 12 : 13))
                .foregroundStyle(Color.primaryText)
                .frame(width: compact ? 54 : 60, height: compact ? 26 : 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Theme.shared.accent.opacity(0.35) : Color.fillSubtle))
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
    }
}

// MARK: - Shared

struct EmptyState: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.secondaryText)
            Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.primaryText)
            Text(subtitle).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
