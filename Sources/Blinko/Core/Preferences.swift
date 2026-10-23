import AppKit
import Observation

enum DisplayMode: String, CaseIterable, Identifiable {
    case notchedOnly, mainOnly, allDisplays
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notchedOnly: "Built-in display"
        case .mainOnly: "Main display"
        case .allDisplays: "All displays"
        }
    }
}

/// Single source of truth for user settings. `@Observable` gives views
/// per-property invalidation, so toggling one setting never redraws the whole notch.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let store = UserDefaults.standard

    // General
    var hasCompletedOnboarding: Bool { didSet { store.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    var displayMode: DisplayMode { didSet { store.set(displayMode.rawValue, forKey: "displayMode") } }
    var showMenuBarIcon: Bool { didSet { store.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    var hideInFullscreen: Bool { didSet { store.set(hideInFullscreen, forKey: "hideInFullscreen") } }

    // Interaction
    var openOnHover: Bool { didSet { store.set(openOnHover, forKey: "openOnHover") } }
    var hoverDelay: Double { didSet { store.set(hoverDelay, forKey: "hoverDelay") } }
    var enableGestures: Bool { didSet { store.set(enableGestures, forKey: "enableGestures") } }
    var enableHaptics: Bool { didSet { store.set(enableHaptics, forKey: "enableHaptics") } }
    var closeOnMouseExit: Bool { didSet { store.set(closeOnMouseExit, forKey: "closeOnMouseExit") } }

    // Live activities
    var musicActivity: Bool { didSet { store.set(musicActivity, forKey: "musicActivity") } }
    var replaceSystemHUD: Bool { didSet { store.set(replaceSystemHUD, forKey: "replaceSystemHUD") } }
    var batteryActivity: Bool { didSet { store.set(batteryActivity, forKey: "batteryActivity") } }
    var bluetoothActivity: Bool { didSet { store.set(bluetoothActivity, forKey: "bluetoothActivity") } }
    var showBatteryInHeader: Bool { didSet { store.set(showBatteryInHeader, forKey: "showBatteryInHeader") } }

    // Appearance
    var artworkTint: Bool { didSet { store.set(artworkTint, forKey: "artworkTint") } }
    var openShadow: Bool { didSet { store.set(openShadow, forKey: "openShadow") } }
    var showVisualizer: Bool { didSet { store.set(showVisualizer, forKey: "showVisualizer") } }

    // Modules
    var showCalendar: Bool { didSet { store.set(showCalendar, forKey: "showCalendar") } }
    var showMirror: Bool { didSet { store.set(showMirror, forKey: "showMirror") } }
    var clipboardHistory: Bool { didSet { store.set(clipboardHistory, forKey: "clipboardHistory") } }
    var clipboardLimit: Int { didSet { store.set(clipboardLimit, forKey: "clipboardLimit") } }
    var shelfAutoOpenOnDrag: Bool { didSet { store.set(shelfAutoOpenOnDrag, forKey: "shelfAutoOpenOnDrag") } }

    var showCredit: Bool { didSet { store.set(showCredit, forKey: "showCredit") } }

    // Clock
    var showClock: Bool { didSet { store.set(showClock, forKey: "showClock") } }
    var showClockInHeader: Bool { didSet { store.set(showClockInHeader, forKey: "showClockInHeader") } }
    var showClockWhenIdle: Bool { didSet { store.set(showClockWhenIdle, forKey: "showClockWhenIdle") } }

    // HUD extras
    var capsLockHUD: Bool { didSet { store.set(capsLockHUD, forKey: "capsLockHUD") } }
    var micHUD: Bool { didSet { store.set(micHUD, forKey: "micHUD") } }

    // Layout
    var openWidth: Double { didSet { store.set(openWidth, forKey: "openWidth") } }
    /// Fine-tunes the closed island width to match the hardware notch exactly.
    var notchWidthOffset: Double { didSet { store.set(notchWidthOffset, forKey: "notchWidthOffset") } }
    var tabOrder: [NotchTab] { didSet { store.set(tabOrder.map(\.rawValue), forKey: "tabOrder") } }
    var hiddenTabs: Set<NotchTab> { didSet { store.set(hiddenTabs.map(\.rawValue), forKey: "hiddenTabs") } }
    var visibleTabs: [NotchTab] {
        let tabs = tabOrder.filter { !hiddenTabs.contains($0) }
        return tabs.isEmpty ? [.home] : tabs
    }

    // Shortcut (Carbon key code + Carbon modifier mask)
    var hotkeyKeyCode: Int { didSet { store.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") } }
    var hotkeyModifiers: Int { didSet { store.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }
    var hotkeyKeyName: String { didSet { store.set(hotkeyKeyName, forKey: "hotkeyKeyName") } }
    var hotkeyEnabled: Bool { didSet { store.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }

    // Pomodoro
    var focusMinutes: Int { didSet { store.set(focusMinutes, forKey: "focusMinutes") } }
    var shortBreakMinutes: Int { didSet { store.set(shortBreakMinutes, forKey: "shortBreakMinutes") } }
    var longBreakMinutes: Int { didSet { store.set(longBreakMinutes, forKey: "longBreakMinutes") } }
    var autoStartNextSession: Bool { didSet { store.set(autoStartNextSession, forKey: "autoStartNextSession") } }

    private init() {
        store.register(defaults: [
            "displayMode": DisplayMode.notchedOnly.rawValue,
            "showMenuBarIcon": true,
            "hideInFullscreen": true,
            "openOnHover": true,
            "hoverDelay": 0.12,
            "enableGestures": true,
            "enableHaptics": true,
            "closeOnMouseExit": true,
            "musicActivity": true,
            "replaceSystemHUD": true,
            "batteryActivity": true,
            "bluetoothActivity": true,
            "showBatteryInHeader": true,
            "artworkTint": true,
            "openShadow": true,
            "showVisualizer": true,
            "showCalendar": true,
            "showMirror": true,
            "clipboardHistory": true,
            "clipboardLimit": 30,
            "shelfAutoOpenOnDrag": true,
            "showCredit": true,
            "showClock": true,
            "showClockInHeader": true,
            "showClockWhenIdle": false,
            "capsLockHUD": true,
            "micHUD": true,
            "openWidth": 700.0,
            "notchWidthOffset": 0.0,
            "tabOrder": NotchTab.allCases.map(\.rawValue),
            "hiddenTabs": [String](),
            "hotkeyKeyCode": 49,           // kVK_Space
            "hotkeyModifiers": 0x1000 | 0x0800, // controlKey | optionKey
            "hotkeyKeyName": "Space",
            "hotkeyEnabled": true,
            "focusMinutes": 25,
            "shortBreakMinutes": 5,
            "longBreakMinutes": 15,
            "autoStartNextSession": true,
        ])
        hasCompletedOnboarding = store.bool(forKey: "hasCompletedOnboarding")
        displayMode = DisplayMode(rawValue: store.string(forKey: "displayMode") ?? "") ?? .notchedOnly
        showMenuBarIcon = store.bool(forKey: "showMenuBarIcon")
        hideInFullscreen = store.bool(forKey: "hideInFullscreen")
        openOnHover = store.bool(forKey: "openOnHover")
        hoverDelay = store.double(forKey: "hoverDelay")
        enableGestures = store.bool(forKey: "enableGestures")
        enableHaptics = store.bool(forKey: "enableHaptics")
        closeOnMouseExit = store.bool(forKey: "closeOnMouseExit")
        musicActivity = store.bool(forKey: "musicActivity")
        replaceSystemHUD = store.bool(forKey: "replaceSystemHUD")
        batteryActivity = store.bool(forKey: "batteryActivity")
        bluetoothActivity = store.bool(forKey: "bluetoothActivity")
        showBatteryInHeader = store.bool(forKey: "showBatteryInHeader")
        artworkTint = store.bool(forKey: "artworkTint")
        openShadow = store.bool(forKey: "openShadow")
        showVisualizer = store.bool(forKey: "showVisualizer")
        showCalendar = store.bool(forKey: "showCalendar")
        showMirror = store.bool(forKey: "showMirror")
        clipboardHistory = store.bool(forKey: "clipboardHistory")
        clipboardLimit = store.integer(forKey: "clipboardLimit")
        shelfAutoOpenOnDrag = store.bool(forKey: "shelfAutoOpenOnDrag")
        showCredit = store.bool(forKey: "showCredit")
        showClock = store.bool(forKey: "showClock")
        showClockInHeader = store.bool(forKey: "showClockInHeader")
        showClockWhenIdle = store.bool(forKey: "showClockWhenIdle")
        capsLockHUD = store.bool(forKey: "capsLockHUD")
        micHUD = store.bool(forKey: "micHUD")
        openWidth = store.double(forKey: "openWidth")
        notchWidthOffset = store.double(forKey: "notchWidthOffset")
        // Keep saved order, append tabs added in newer versions.
        var order = (store.stringArray(forKey: "tabOrder") ?? []).compactMap(NotchTab.init(rawValue:))
        order += NotchTab.allCases.filter { !order.contains($0) }
        tabOrder = order
        hiddenTabs = Set((store.stringArray(forKey: "hiddenTabs") ?? []).compactMap(NotchTab.init(rawValue:)))
        hotkeyKeyCode = store.integer(forKey: "hotkeyKeyCode")
        hotkeyModifiers = store.integer(forKey: "hotkeyModifiers")
        hotkeyKeyName = store.string(forKey: "hotkeyKeyName") ?? "Space"
        hotkeyEnabled = store.bool(forKey: "hotkeyEnabled")
        focusMinutes = store.integer(forKey: "focusMinutes")
        shortBreakMinutes = store.integer(forKey: "shortBreakMinutes")
        longBreakMinutes = store.integer(forKey: "longBreakMinutes")
        autoStartNextSession = store.bool(forKey: "autoStartNextSession")
    }
}
