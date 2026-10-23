import Foundation
import SwiftUI

// MARK: - Widget sizes

/// Width class of a Home widget. The Home content area is a row of columns worth
/// `HomeLayout.capacity` units: Small = 2, Medium = 3, Large = 5. Small and Medium columns
/// have fixed design widths; Large columns share whatever is left, so a layout always fits
/// the open island at every size preset.
enum HomeWidgetSize: String, Codable, CaseIterable, Identifiable, Comparable {
    case small, medium, large
    var id: String { rawValue }

    var units: Int {
        switch self {
        case .small: 2
        case .medium: 3
        case .large: 5
        }
    }

    /// Design width (pt, at the 700 pt island) of a fixed column; nil = flexible.
    var fixedWidth: CGFloat? {
        switch self {
        case .small: 112
        case .medium: 176
        case .large: nil
        }
    }

    var letter: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.units < b.units }
}

// MARK: - Widget catalog

/// Every widget Home can show. Each one is a self-contained view in Views/Expanded/Widgets
/// that reads its own service at the leaf, so a widget that is not on the layout does no work.
enum HomeWidgetKind: String, Codable, CaseIterable, Identifiable {
    case nowPlaying, today, clock, agenda, weather, timers, stats, agents, notes, mirror, battery, shelf, clipboard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: String(localized: "Now Playing")
        case .today: String(localized: "Clock & Agenda")
        case .clock: String(localized: "Clock")
        case .agenda: String(localized: "Calendar")
        case .weather: String(localized: "Weather")
        case .timers: String(localized: "Timers & Focus")
        case .stats: String(localized: "System Stats")
        case .agents: String(localized: "Agents")
        case .notes: String(localized: "Notes")
        case .mirror: String(localized: "Mirror")
        case .battery: String(localized: "Battery")
        case .shelf: String(localized: "Shelf")
        case .clipboard: String(localized: "Clipboard")
        }
    }

    var subtitle: String {
        switch self {
        case .nowPlaying: String(localized: "Player with lyrics; the meeting card during a call")
        case .today: String(localized: "Clock, world clocks, weather and your next events")
        case .clock: String(localized: "Time, date and world clocks")
        case .agenda: String(localized: "Today's events and reminders")
        case .weather: String(localized: "Conditions and the next hours")
        case .timers: String(localized: "Countdowns and Pomodoro")
        case .stats: String(localized: "CPU, memory and network")
        case .agents: String(localized: "Coding agents from the Agent Hub")
        case .notes: String(localized: "The Notes scratchpad")
        case .mirror: String(localized: "Camera mirror, on when you click it")
        case .battery: String(localized: "Charge and time remaining")
        case .shelf: String(localized: "Latest files on the shelf")
        case .clipboard: String(localized: "Latest copied items")
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "play.circle.fill"
        case .today: "calendar.day.timeline.left"
        case .clock: "clock.fill"
        case .agenda: "calendar"
        case .weather: "cloud.sun.fill"
        case .timers: "timer"
        case .stats: "gauge.with.dots.needle.67percent"
        case .agents: "sparkles.rectangle.stack.fill"
        case .notes: "note.text"
        case .mirror: "camera.fill"
        case .battery: "battery.75percent"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        }
    }

    var tint: Color {
        switch self {
        case .nowPlaying: .pink
        case .today: .red
        case .clock: .orange
        case .agenda: .red
        case .weather: .cyan
        case .timers: .orange
        case .stats: .teal
        case .agents: .agentAccent
        case .notes: .yellow
        case .mirror: .gray
        case .battery: .green
        case .shelf: .blue
        case .clipboard: .indigo
        }
    }

    /// Sizes this widget can take, smallest first.
    var sizes: [HomeWidgetSize] {
        switch self {
        case .nowPlaying: [.medium, .large]
        case .today: [.medium]
        case .clock: [.small, .medium]
        case .agenda: [.medium, .large]
        case .weather: [.small, .medium]
        case .timers: [.small, .medium, .large]
        case .stats: [.small, .medium]
        case .agents: [.small, .medium, .large]
        case .notes: [.medium, .large]
        case .mirror: [.small, .medium]
        case .battery: [.small]
        case .shelf: [.small, .medium, .large]
        case .clipboard: [.small, .medium, .large]
        }
    }

    var defaultSize: HomeWidgetSize {
        switch self {
        case .nowPlaying: .large
        case .today, .agenda, .notes: .medium
        default: sizes[0]
        }
    }

    /// Bare widgets sit straight on the island (player, clock and agenda columns, as Home has
    /// always looked); the others are cards. Two adjacent bare widgets get a hairline between them.
    func isBare(_ size: HomeWidgetSize) -> Bool {
        switch self {
        case .nowPlaying: size == .large
        case .today, .agenda: true
        case .clock: size == .medium
        default: false
        }
    }
}

// MARK: - Layout

struct HomeSlot: Codable, Identifiable, Equatable {
    var id: UUID
    var widget: HomeWidgetKind
    var size: HomeWidgetSize

    init(id: UUID = UUID(), _ widget: HomeWidgetKind, _ size: HomeWidgetSize? = nil) {
        self.id = id
        self.widget = widget
        self.size = size ?? widget.defaultSize
    }
}

/// A named arrangement of Home widgets. Built-ins have ids starting with "builtin."; edits to a
/// built-in are saved as a new custom layout. Persisted as JSON in Preferences.
struct HomeLayout: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var slots: [HomeSlot]

    static let capacity = 10
    static let defaultID = "builtin.default"

    var isBuiltIn: Bool { id.hasPrefix("builtin.") }
    var units: Int { slots.reduce(0) { $0 + $1.size.units } }
    var freeUnits: Int { Self.capacity - units }

    /// Whether `slot` could take `size` (the rest of the layout unchanged).
    func canResize(_ slot: HomeSlot, to size: HomeWidgetSize) -> Bool {
        slot.widget.sizes.contains(size) && units - slot.size.units + size.units <= Self.capacity
    }

    /// Largest preferred size that still fits when adding `widget` (default size first).
    func fittingSize(for widget: HomeWidgetKind, replacing slot: HomeSlot? = nil) -> HomeWidgetSize? {
        let free = freeUnits + (slot?.size.units ?? 0)
        let preferred = [widget.defaultSize] + widget.sizes.reversed()
        if let keep = slot?.size, widget.sizes.contains(keep) { return keep }
        return preferred.first { $0.units <= free }
    }

    /// Whether Home already shows the time (the header then leaves it out).
    @MainActor var showsClock: Bool {
        slots.contains { $0.widget == .clock || ($0.widget == .today && Preferences.shared.showClock) }
    }

    /// Whether Home already shows the weather (the header then leaves it out). The Clock &
    /// Agenda widget carries its weather chip beside the clock.
    @MainActor var showsWeather: Bool {
        slots.contains { $0.widget == .weather || ($0.widget == .today && Preferences.shared.showClock) }
    }

    /// Drops unknown / invalid entries and anything beyond the capacity.
    func sanitized() -> HomeLayout {
        var out = self
        var used = 0
        var seen = Set<UUID>()
        out.slots = slots.compactMap { slot in
            var slot = slot
            if !slot.widget.sizes.contains(slot.size) { slot.size = slot.widget.sizes[0] }
            guard !seen.contains(slot.id), used + slot.size.units <= Self.capacity else { return nil }
            seen.insert(slot.id)
            used += slot.size.units
            return slot
        }
        return out
    }

    // Lossy decoding: a widget a newer version added is skipped instead of losing the layout.
    private enum CodingKeys: String, CodingKey { case id, name, slots }
    private struct LossySlot: Decodable {
        let slot: HomeSlot?
        init(from decoder: Decoder) throws { slot = try? HomeSlot(from: decoder) }
    }

    init(id: String, name: String, slots: [HomeSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        slots = try c.decode([LossySlot].self, forKey: .slots).compactMap(\.slot)
    }

    static func decodeList(_ data: Data?) -> [HomeLayout] {
        guard let data, let list = try? JSONDecoder().decode([HomeLayout].self, from: data) else { return [] }
        return list.filter { !$0.isBuiltIn }.map { $0.sanitized() }
    }

    static func encodeList(_ list: [HomeLayout]) -> Data? { try? JSONEncoder().encode(list) }
}

// MARK: - Built-ins

extension HomeLayout {
    /// Stable slot ids for built-ins, so SwiftUI keeps their views when switching layouts.
    private static func fixed(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    /// "Default" is Home as it has always looked, still following the Modules toggles:
    /// player | clock & agenda (when clock, calendar or weather is on) | mirror (when on).
    @MainActor static var standard: HomeLayout {
        let p = Preferences.shared
        var slots = [HomeSlot(id: fixed(1), .nowPlaying, .large)]
        if p.showCalendar || p.showClock || p.weatherEnabled { slots.append(HomeSlot(id: fixed(2), .today, .medium)) }
        if p.showMirror { slots.append(HomeSlot(id: fixed(3), .mirror, .small)) }
        return HomeLayout(id: defaultID, name: String(localized: "Default"), slots: slots)
    }

    static var work: HomeLayout {
        HomeLayout(id: "builtin.work", name: String(localized: "Work"), slots: [
            HomeSlot(id: fixed(11), .agenda, .medium),
            HomeSlot(id: fixed(12), .timers, .small),
            HomeSlot(id: fixed(13), .agents, .small),
            HomeSlot(id: fixed(14), .notes, .medium),
        ])
    }

    static var chill: HomeLayout {
        HomeLayout(id: "builtin.chill", name: String(localized: "Chill"), slots: [
            HomeSlot(id: fixed(1), .nowPlaying, .large),
            HomeSlot(id: fixed(21), .weather, .medium),
            HomeSlot(id: fixed(22), .clock, .small),
        ])
    }

    @MainActor static var builtIns: [HomeLayout] { [standard, work, chill] }
}

// MARK: - Store

/// Reading and editing layouts. State lives in Preferences (`homeLayouts`, `homeLayoutID`),
/// so views observing the current layout redraw only when it changes.
@MainActor
enum HomeLayouts {
    static var all: [HomeLayout] { HomeLayout.builtIns + Preferences.shared.homeLayouts }

    static var current: HomeLayout {
        let p = Preferences.shared
        switch p.homeLayoutID {
        case HomeLayout.defaultID: return .standard
        case HomeLayout.work.id: return .work
        case HomeLayout.chill.id: return .chill
        default: return p.homeLayouts.first { $0.id == p.homeLayoutID } ?? .standard
        }
    }

    static func select(_ id: String) {
        let p = Preferences.shared
        guard p.homeLayoutID != id, all.contains(where: { $0.id == id }) else { return }
        p.homeLayoutID = id
    }

    /// Applies an edit to the current layout. Editing a built-in saves a custom copy first.
    @discardableResult
    static func edit(_ change: (inout HomeLayout) -> Void) -> Bool {
        var layout = current
        let before = layout
        change(&layout)
        layout = layout.sanitized()
        guard layout.slots != before.slots || layout.name != before.name else { return false }
        let p = Preferences.shared
        if layout.isBuiltIn {
            layout.id = UUID().uuidString
            layout.name = uniqueName(String(localized: "My Layout"))
            p.homeLayouts.append(layout)
            p.homeLayoutID = layout.id
        } else if let i = p.homeLayouts.firstIndex(where: { $0.id == layout.id }) {
            p.homeLayouts[i] = layout
        }
        return true
    }

    /// Saves a copy of the current layout under a new name and selects it.
    static func duplicateCurrent() {
        var copy = current
        copy.id = UUID().uuidString
        copy.name = uniqueName(copy.isBuiltIn ? String(localized: "My \(current.name)") : current.name)
        copy.slots = copy.slots.map { HomeSlot($0.widget, $0.size) }
        Preferences.shared.homeLayouts.append(copy)
        Preferences.shared.homeLayoutID = copy.id
    }

    static func deleteCurrent() {
        let p = Preferences.shared
        guard !current.isBuiltIn else { return }
        let id = current.id
        p.homeLayouts.removeAll { $0.id == id }
        p.homeLayoutID = HomeLayout.defaultID
    }

    static func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !current.isBuiltIn else { return }
        edit { $0.name = String(trimmed.prefix(40)) }
    }

    private static func uniqueName(_ base: String) -> String {
        let names = Set(all.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Slot operations (all keep the layout within capacity)

    /// Appends a widget at its preferred size that fits; false if there is no room.
    @discardableResult
    static func add(_ widget: HomeWidgetKind, at index: Int? = nil) -> Bool {
        guard let size = current.fittingSize(for: widget) else { return false }
        return edit { layout in
            let i = min(index ?? layout.slots.count, layout.slots.count)
            layout.slots.insert(HomeSlot(widget, size), at: i)
        }
    }

    /// Puts `widget` in place of a slot, keeping its size when the widget allows it.
    static func replace(_ slotID: UUID, with widget: HomeWidgetKind) {
        let layout = current
        guard let slot = layout.slots.first(where: { $0.id == slotID }), slot.widget != widget,
              let size = layout.fittingSize(for: widget, replacing: slot) else { return }
        edit { l in
            if let i = l.slots.firstIndex(where: { $0.id == slotID }) { l.slots[i] = HomeSlot(widget, size) }
        }
    }

    static func remove(_ slotID: UUID) {
        edit { $0.slots.removeAll { $0.id == slotID } }
    }

    static func resize(_ slotID: UUID, to size: HomeWidgetSize) {
        let layout = current
        guard let slot = layout.slots.first(where: { $0.id == slotID }), layout.canResize(slot, to: size) else { return }
        edit { l in
            if let i = l.slots.firstIndex(where: { $0.id == slotID }) { l.slots[i].size = size }
        }
    }

    /// Next size up that fits, wrapping round to the smallest.
    static func cycleSize(_ slotID: UUID) {
        let layout = current
        guard let slot = layout.slots.first(where: { $0.id == slotID }) else { return }
        let sizes = slot.widget.sizes
        guard let i = sizes.firstIndex(of: slot.size) else { return }
        for step in 1..<max(sizes.count, 2) {
            let candidate = sizes[(i + step) % sizes.count]
            if layout.canResize(slot, to: candidate) { resize(slotID, to: candidate); return }
        }
    }

    /// Moves a slot to `index` (the index it should have afterwards).
    static func move(_ slotID: UUID, to index: Int) {
        edit { l in
            guard let from = l.slots.firstIndex(where: { $0.id == slotID }) else { return }
            let slot = l.slots.remove(at: from)
            l.slots.insert(slot, at: min(max(index, 0), l.slots.count))
        }
    }
}
