import Foundation
import Observation

/// Lock-screen settings (v0.5, experimental). Kept beside `Preferences` in the same
/// didSet + registered-defaults style, in their own type so the feature stays self-contained.
@MainActor
@Observable
final class LockScreenSettings {
    static let shared = LockScreenSettings()

    @ObservationIgnored private let store = UserDefaults.standard

    /// Master switch. Off by default: it relies on private SkyLight API.
    var enabled: Bool { didSet { store.set(enabled, forKey: "lockScreenEnabled") } }

    // The island at the notch
    var showIsland: Bool { didSet { store.set(showIsland, forKey: "lockScreenIsland") } }
    var islandMusic: Bool { didSet { store.set(islandMusic, forKey: "lockScreenIslandMusic") } }
    var islandCharging: Bool { didSet { store.set(islandCharging, forKey: "lockScreenIslandCharging") } }
    var islandTimer: Bool { didSet { store.set(islandTimer, forKey: "lockScreenIslandTimer") } }

    // Widget panel
    var showWidgets: Bool { didSet { store.set(showWidgets, forKey: "lockScreenWidgets") } }
    var widgetMusic: Bool { didSet { store.set(widgetMusic, forKey: "lockScreenWidgetMusic") } }
    var widgetBattery: Bool { didSet { store.set(widgetBattery, forKey: "lockScreenWidgetBattery") } }
    var widgetCalendar: Bool { didSet { store.set(widgetCalendar, forKey: "lockScreenWidgetCalendar") } }
    var widgetTimer: Bool { didSet { store.set(widgetTimer, forKey: "lockScreenWidgetTimer") } }
    /// Moves the widget panel up or down from its default spot below the screen centre (pt).
    var widgetOffset: Double { didSet { store.set(widgetOffset, forKey: "lockScreenWidgetOffset") } }

    // Privacy
    /// Event titles on the lock screen; otherwise only the time and "Event".
    var calendarDetails: Bool { didSet { store.set(calendarDetails, forKey: "lockScreenCalendarDetails") } }
    /// AI agent status (project names, tools) in the closed island.
    var showAgents: Bool { didSet { store.set(showAgents, forKey: "lockScreenAgents") } }

    private init() {
        store.register(defaults: [
            "lockScreenEnabled": false,
            "lockScreenIsland": true,
            "lockScreenIslandMusic": true,
            "lockScreenIslandCharging": true,
            "lockScreenIslandTimer": true,
            "lockScreenWidgets": true,
            "lockScreenWidgetMusic": true,
            "lockScreenWidgetBattery": true,
            "lockScreenWidgetCalendar": true,
            "lockScreenWidgetTimer": true,
            "lockScreenWidgetOffset": 0.0,
            "lockScreenCalendarDetails": false,
            "lockScreenAgents": false,
        ])
        enabled = store.bool(forKey: "lockScreenEnabled")
        showIsland = store.bool(forKey: "lockScreenIsland")
        islandMusic = store.bool(forKey: "lockScreenIslandMusic")
        islandCharging = store.bool(forKey: "lockScreenIslandCharging")
        islandTimer = store.bool(forKey: "lockScreenIslandTimer")
        showWidgets = store.bool(forKey: "lockScreenWidgets")
        widgetMusic = store.bool(forKey: "lockScreenWidgetMusic")
        widgetBattery = store.bool(forKey: "lockScreenWidgetBattery")
        widgetCalendar = store.bool(forKey: "lockScreenWidgetCalendar")
        widgetTimer = store.bool(forKey: "lockScreenWidgetTimer")
        widgetOffset = store.double(forKey: "lockScreenWidgetOffset")
        calendarDetails = store.bool(forKey: "lockScreenCalendarDetails")
        showAgents = store.bool(forKey: "lockScreenAgents")
    }
}
