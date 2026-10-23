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
            .fill(selected ? Color.accentColor.opacity(0.3) : (hovering ? Color.fillSubtle : .clear)))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .onTapGesture(count: 2) { shelf.open(item) }
        .onTapGesture {
            if shelf.selection.contains(item.id) { shelf.selection.remove(item.id) } else { shelf.selection.insert(item.id) }
        }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
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

private struct DropActionTile: View {
    let symbol: String
    let title: String
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
                Text(item.sourceApp ?? "Copied")
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
                     detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores",
                     history: stats.cpuHistory, tint: .cyan, normalize: false)
            StatCard(title: "Memory", value: Format.bytes(stats.memoryUsed),
                     detail: "of " + Format.bytes(stats.memoryTotal),
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
    let title: String
    let value: String
    let detail: String
    let history: [Double]
    let tint: Color
    let normalize: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
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
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
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
        if b.isCharging { parts.append("Charging") } else if b.isPluggedIn { parts.append("Plugged in") }
        if let m = b.minutesRemaining { parts.append("\(m / 60)h \(m % 60)m") }
        if b.isLowPowerMode { parts.append("Low Power") }
        return parts.isEmpty ? "On battery" : parts.joined(separator: " · ")
    }
}

// MARK: - Timer

struct TimerView: View {
    private let presets: [(String, TimeInterval)] = [("1m", 60), ("5m", 300), ("10m", 600), ("25m", 1500), ("45m", 2700), ("1h", 3600)]

    var body: some View {
        let timer = TimerService.shared
        HStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: timer.isRunning ? 0.25 : 3600)) { ctx in
                ZStack {
                    RingProgress(value: timer.isActive ? 1 - timer.progress(at: ctx.date) : 0, tint: .orange, lineWidth: 6)
                    VStack(spacing: 2) {
                        Text(Format.time(timer.isActive ? timer.remaining(at: ctx.date).rounded(.up) : 0))
                            .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.primaryText)
                            .contentTransition(.numericText(countsDown: true))
                        Text(timer.isPaused ? "Paused" : (timer.isRunning ? "Remaining" : "Ready"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.tertiaryText)
                    }
                }
                .frame(width: 128, height: 128)
                .animation(.linear(duration: 0.25), value: timer.progress(at: ctx.date))
            }

            VStack(alignment: .leading, spacing: 12) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(presets[(row * 3)..<(row * 3 + 3)], id: \.1) { preset in
                                PresetChip(title: preset.0) { timer.start(preset.1) }
                            }
                        }
                    }
                }
                .fixedSize()
                HStack(spacing: 8) {
                    if timer.isActive {
                        PillButton(title: timer.isPaused ? "Resume" : "Pause",
                                   symbol: timer.isPaused ? "play.fill" : "pause.fill", prominent: true) {
                            timer.isPaused ? timer.resume() : timer.pause()
                        }
                        PillButton(title: "+1 min", symbol: "plus") { timer.add(60) }
                        PillButton(title: "Cancel", symbol: "xmark") { timer.cancel() }
                    } else {
                        Text("Pick a duration to start")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.tertiaryText)
                    }
                }
                .animation(Motion.micro, value: timer.isActive)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PresetChip: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primaryText)
                .frame(width: 64, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.orange.opacity(0.35) : Color.fillSubtle))
        }
        .buttonStyle(PressableStyle(scale: 0.93))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
    }
}

// MARK: - Shared

struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

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
