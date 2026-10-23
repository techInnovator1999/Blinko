import SwiftUI

/// Home: the widgets of the selected layout (Core/HomeLayout.swift), side by side in
/// fixed-width columns. Only the widgets on the layout exist as views, so a widget that is
/// not placed starts no work (stats sampling, camera, timelines). Each widget observes its
/// own service at the leaf; this view only reads the layout.
struct HomeView: View {
    let vm: NotchViewModel

    var body: some View {
        HomeGrid(layout: HomeLayouts.current, vm: vm)
    }
}

/// While true, Home draws its edit chrome (Settings → Home Layout preview): slots can be
/// dragged, resized and removed, and widgets dropped in. Widgets stop taking clicks.
private struct HomeLayoutEditingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var homeLayoutEditing: Bool {
        get { self[HomeLayoutEditingKey.self] }
        set { self[HomeLayoutEditingKey.self] = newValue }
    }
}

// MARK: - Layout switching

/// Right-click menu on the Home tab button: switch layouts, or edit them in Settings.
private struct HomeLayoutMenu: ViewModifier {
    let enabled: Bool
    let vm: NotchViewModel

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { HomeLayoutMenuItems(vm: vm) }
        } else {
            content
        }
    }
}

extension View {
    func homeLayoutMenu(enabled: Bool, vm: NotchViewModel) -> some View {
        modifier(HomeLayoutMenu(enabled: enabled, vm: vm))
    }
}

struct HomeLayoutMenuItems: View {
    let vm: NotchViewModel

    var body: some View {
        let current = HomeLayouts.current.id
        Picker("Home Layout", selection: Binding(get: { current }, set: { id in
            withAnimation(Motion.micro) {
                HomeLayouts.select(id)
                vm.tab = .home
            }
        })) {
            ForEach(HomeLayouts.all) { layout in
                Text(verbatim: layout.name).tag(layout.id)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Button("Edit Home Layout…") { WidgetActions.openSettings(.homeLayout, vm: vm) }
    }
}

// MARK: - Grid

struct HomeGrid: View {
    let layout: HomeLayout
    let vm: NotchViewModel
    @Environment(\.homeLayoutEditing) private var editing

    var body: some View {
        if layout.slots.isEmpty, !editing {
            EmptyHome(vm: vm)
        } else {
            HomeColumns(spacing: 14) {
                ForEach(columns) { column in
                    switch column.kind {
                    case .divider:
                        HStack { Divider() } // vertical, as in an HStack
                            .overlay(Color.hairline)
                            .frame(height: 120)
                            .padding(.top, 8)
                            .layoutValue(key: HomeColumnKey.self, value: .divider)
                    case .slot(let slot, let index):
                        HomeSlotView(slot: slot, index: index, vm: vm)
                            .layoutValue(key: HomeColumnKey.self, value: slot.size.fixedWidth.map(HomeColumnWidth.fixed) ?? .flex)
                    case .add(let free):
                        HomeAddZone(free: free)
                            .layoutValue(key: HomeColumnKey.self, value: HomeAddZone.width(free: free))
                    }
                }
            }
            .animation(Motion.micro, value: layout.slots)
        }
    }

    private struct Column: Identifiable {
        enum Kind { case divider, slot(HomeSlot, Int), add(Int) }
        let id: String
        let kind: Kind
    }

    /// Slots in order, a hairline between two adjacent bare widgets, and (while editing) a
    /// drop zone for the room that is left.
    private var columns: [Column] {
        var out: [Column] = []
        var previousBare = false
        for (i, slot) in layout.slots.enumerated() {
            let bare = slot.widget.isBare(slot.size)
            if bare, previousBare { out.append(Column(id: "divider-\(slot.id)", kind: .divider)) }
            out.append(Column(id: slot.id.uuidString, kind: .slot(slot, i)))
            previousBare = bare
        }
        if editing, layout.freeUnits >= HomeWidgetSize.small.units {
            out.append(Column(id: "add", kind: .add(layout.freeUnits)))
        }
        return out
    }
}

/// How wide a Home column is: a fixed design width, a share of what is left, or a hairline.
enum HomeColumnWidth: Equatable {
    case fixed(CGFloat)
    case flex
    case divider
}

private struct HomeColumnKey: LayoutValueKey {
    static let defaultValue = HomeColumnWidth.flex
}

/// Lays Home's columns out left to right. Fixed columns keep their width and flexible
/// (Large) columns share the rest. Without a Large column the fixed ones stretch a little
/// (at most 1.5×) to fill the row and the group is centered. If the island is narrower than
/// the design (custom widths), fixed columns give way before Large ones drop under 240 pt.
struct HomeColumns: Layout {
    var spacing: CGFloat = 14
    static let minFlex: CGFloat = 240

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 638
        let (widths, _) = columnWidths(width, subviews)
        var height: CGFloat = 0
        for (view, w) in zip(subviews, widths) {
            height = max(height, view.sizeThatFits(ProposedViewSize(width: w, height: proposal.height)).height)
        }
        return CGSize(width: width, height: min(height, proposal.height ?? height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (widths, inset) = columnWidths(bounds.width, subviews)
        var x = bounds.minX + inset
        for (view, w) in zip(subviews, widths) {
            view.place(at: CGPoint(x: x + w / 2, y: bounds.minY), anchor: .top,
                       proposal: ProposedViewSize(width: w, height: proposal.height ?? bounds.height))
            x += w + spacing
        }
    }

    /// Column widths and the leading inset that centers them.
    private func columnWidths(_ width: CGFloat, _ subviews: Subviews) -> ([CGFloat], CGFloat) {
        let kinds = subviews.map { $0[HomeColumnKey.self] }
        guard !kinds.isEmpty else { return ([], 0) }
        let available = max(0, width - spacing * CGFloat(kinds.count - 1))
        var fixedTotal: CGFloat = 0, dividers: CGFloat = 0, flexCount: CGFloat = 0
        for kind in kinds {
            switch kind {
            case .fixed(let w): fixedTotal += w
            case .divider: dividers += 1
            case .flex: flexCount += 1
            }
        }
        let room = available - dividers
        var scale: CGFloat = 1
        var flex: CGFloat = 0
        var inset: CGFloat = 0
        if flexCount > 0 {
            flex = (room - fixedTotal) / flexCount
            if flex < Self.minFlex, fixedTotal > 0 {
                scale = max(0.6, (room - Self.minFlex * flexCount) / fixedTotal)
                flex = max(0, (room - fixedTotal * scale) / flexCount)
            }
        } else if fixedTotal > 0 {
            scale = min(room / fixedTotal, 1.5)
            inset = max(0, (room - fixedTotal * scale) / 2)
        }
        let widths = kinds.map { kind -> CGFloat in
            switch kind {
            case .fixed(let w): w * scale
            case .divider: 1
            case .flex: flex
            }
        }
        return (widths, inset)
    }
}

// MARK: - Slot

/// One widget in its column, plus the edit chrome while the layout is being edited.
private struct HomeSlotView: View {
    let slot: HomeSlot
    let index: Int
    let vm: NotchViewModel
    @Environment(\.homeLayoutEditing) private var editing

    var body: some View {
        if editing {
            HomeWidgetContent(slot: slot, vm: vm)
                .allowsHitTesting(false)
                .opacity(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .overlay { HomeSlotEditor(slot: slot, index: index) }
        } else {
            HomeWidgetContent(slot: slot, vm: vm)
        }
    }
}

/// The widget view for a slot. Cards get the shared card frame; bare widgets lay out as Home
/// always has (player fills its column leading, the agenda column is centered in its width).
struct HomeWidgetContent: View {
    let slot: HomeSlot
    let vm: NotchViewModel

    var body: some View {
        let size = slot.size
        switch slot.widget {
        case .nowPlaying:
            if size == .large {
                HomePrimaryView() // media player, or the meeting card during a call
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                NowPlayingCard().widgetCardFrame()
            }
        case .today:
            AgendaView()
        case .clock:
            if size == .small {
                ClockCard().widgetCardFrame()
            } else {
                ClockColumn().frame(maxWidth: .infinity, alignment: .leading)
            }
        case .agenda:
            AgendaListWidget(size: size).frame(maxWidth: .infinity, alignment: .leading)
        case .weather:
            WeatherWidget(size: size, vm: vm).widgetCardFrame()
        case .timers:
            TimersWidget(size: size).widgetCardFrame()
        case .stats:
            StatsWidget(size: size).widgetCardFrame()
        case .agents:
            AgentsWidget(size: size, vm: vm).widgetCardFrame()
        case .notes:
            NotesWidget(vm: vm).widgetCardFrame()
        case .mirror:
            MirrorTile().widgetCardFrame()
        case .battery:
            BatteryWidget().widgetCardFrame()
        case .shelf:
            ShelfWidget(size: size, vm: vm).widgetCardFrame()
        case .clipboard:
            ClipboardWidget(size: size).widgetCardFrame()
        }
    }
}

/// A layout with no widgets.
private struct EmptyHome: View {
    let vm: NotchViewModel

    var body: some View {
        VStack(spacing: 8) {
            EmptyState(symbol: "square.grid.3x2", title: "Home is empty",
                       subtitle: "Add widgets in Settings → Home Layout")
                .frame(height: 90)
            PillButton(title: "Edit Layout…", symbol: "square.grid.3x2.fill") {
                WidgetActions.openSettings(.homeLayout, vm: vm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Edit chrome

/// Drag payloads between the palette, the slots and the drop zone.
enum HomeDragItem {
    static func widget(_ kind: HomeWidgetKind) -> String { "blinko-widget:" + kind.rawValue }
    static func slot(_ id: UUID) -> String { "blinko-slot:" + id.uuidString }

    enum Parsed { case widget(HomeWidgetKind), slot(UUID) }

    static func parse(_ string: String) -> Parsed? {
        if string.hasPrefix("blinko-widget:") {
            return HomeWidgetKind(rawValue: String(string.dropFirst("blinko-widget:".count))).map(Parsed.widget)
        }
        if string.hasPrefix("blinko-slot:") {
            return UUID(uuidString: String(string.dropFirst("blinko-slot:".count))).map(Parsed.slot)
        }
        return nil
    }
}

/// Outline, title, size switch and remove button over a slot. The whole slot drags to
/// reorder; dropping a widget on it inserts it there (or replaces it when Home is full).
private struct HomeSlotEditor: View {
    let slot: HomeSlot
    let index: Int
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        let accent = Theme.shared.accent
        let layout = HomeLayouts.current
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            shape.fill(Color.black.opacity(targeted ? 0.4 : 0.62))
            shape.strokeBorder(targeted ? accent : Color.white.opacity(hovering ? 0.5 : 0.28),
                               style: StrokeStyle(lineWidth: targeted ? 2.5 : 1.5, dash: targeted ? [] : [6, 4]))
            VStack(spacing: 4) {
                Image(systemName: slot.widget.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(slot.widget.tint)
                Text(slot.widget.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if targeted {
                    Text(layout.freeUnits >= HomeWidgetSize.small.units ? "Drop to insert" : "Drop to replace")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 6)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation(Motion.micro) { HomeLayouts.remove(slot.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(white: 0.28)))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help("Remove \(slot.widget.title)")
            .offset(x: 6, y: -6)
        }
        .overlay(alignment: .bottom) {
            SizeSwitch(slot: slot, layout: layout).padding(.bottom, 8)
        }
        .padding(.top, 4)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .draggable(HomeDragItem.slot(slot.id)) {
            Label(slot.widget.title, systemImage: slot.widget.symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.regularMaterial))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first.flatMap(HomeDragItem.parse) else { return false }
            withAnimation(Motion.micro) {
                switch item {
                case .widget(let kind):
                    if !HomeLayouts.add(kind, at: index) { HomeLayouts.replace(slot.id, with: kind) }
                case .slot(let id):
                    HomeLayouts.move(id, to: index)
                }
            }
            return true
        } isTargeted: { targeted = $0 }
        .animation(Motion.micro, value: targeted)
    }
}

/// S / M / L capsule: the sizes this widget supports; sizes that don't fit are dimmed.
private struct SizeSwitch: View {
    let slot: HomeSlot
    let layout: HomeLayout

    var body: some View {
        let accent = Theme.shared.accent
        HStack(spacing: 1) {
            ForEach(slot.widget.sizes) { size in
                let selected = size == slot.size
                let fits = layout.canResize(slot, to: size)
                Button {
                    withAnimation(Motion.micro) { HomeLayouts.resize(slot.id, to: size) }
                } label: {
                    Text(verbatim: size.letter)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(selected ? Theme.shared.onAccent : (fits ? .primaryText : .tertiaryText))
                        .frame(width: 22, height: 18)
                        .background(Capsule().fill(selected ? accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .disabled(!fits && !selected)
                .help(size.title)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(white: 0.16)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
    }
}

/// Free room at the end of the row while editing: drop a widget (or a slot) here to append it.
private struct HomeAddZone: View {
    let free: Int
    @State private var targeted = false

    static func width(free: Int) -> HomeColumnWidth {
        if free >= HomeWidgetSize.large.units { return .flex }
        return .fixed(free >= HomeWidgetSize.medium.units ? HomeWidgetSize.medium.fixedWidth! : HomeWidgetSize.small.fixedWidth!)
    }

    var body: some View {
        let accent = Theme.shared.accent
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            shape.fill(targeted ? accent.opacity(0.14) : Color.white.opacity(0.03))
            shape.strokeBorder(targeted ? accent : Color.white.opacity(0.22),
                               style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [6, 4]))
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("Drop a widget")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("\(free) of \(HomeLayout.capacity) units free")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
            }
            .foregroundStyle(targeted ? accent : .secondaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first.flatMap(HomeDragItem.parse) else { return false }
            withAnimation(Motion.micro) {
                switch item {
                case .widget(let kind): HomeLayouts.add(kind)
                case .slot(let id): HomeLayouts.move(id, to: .max)
                }
            }
            return true
        } isTargeted: { targeted = $0 }
        .animation(Motion.micro, value: targeted)
    }
}
