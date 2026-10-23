import AppKit
import Observation

enum DisplayMode: String, CaseIterable, Identifiable {
    case notchedOnly, mainOnly, allDisplays
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notchedOnly: String(localized: "Built-in display")
        case .mainOnly: String(localized: "Main display")
        case .allDisplays: String(localized: "All displays")
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
    var focusActivity: Bool { didSet { store.set(focusActivity, forKey: "focusActivity") } }
    var privacyIndicators: Bool { didSet { store.set(privacyIndicators, forKey: "privacyIndicators") } }
    var downloadsActivity: Bool { didSet { store.set(downloadsActivity, forKey: "downloadsActivity") } }
    var networkActivity: Bool { didSet { store.set(networkActivity, forKey: "networkActivity") } }
    var airPodsBattery: Bool { didSet { store.set(airPodsBattery, forKey: "airPodsBattery") } }

    // Appearance
    var artworkTint: Bool { didSet { store.set(artworkTint, forKey: "artworkTint") } }
    var openShadow: Bool { didSet { store.set(openShadow, forKey: "openShadow") } }
    var showVisualizer: Bool { didSet { store.set(showVisualizer, forKey: "showVisualizer") } }
    /// Forces reduced motion on; the system Accessibility setting is always honoured as well.
    var reduceMotion: Bool { didSet { store.set(reduceMotion, forKey: "reduceMotion") } }
    // Theme (derived values live in Theme.swift)
    var accentPreset: AccentPreset { didSet { store.set(accentPreset.rawValue, forKey: "accentPreset") } }
    var customAccentHex: String { didSet { store.set(customAccentHex, forKey: "customAccentHex") } }
    var islandStyle: IslandStyle { didSet { store.set(islandStyle.rawValue, forKey: "islandStyle") } }
    var openCornerRadius: Double { didSet { store.set(openCornerRadius, forKey: "openCornerRadius") } }
    var closedCornerRadius: Double { didSet { store.set(closedCornerRadius, forKey: "closedCornerRadius") } }
    var fontStyle: FontStyle { didSet { store.set(fontStyle.rawValue, forKey: "fontStyle") } }

    // Lyrics
    var showLyrics: Bool { didSet { store.set(showLyrics, forKey: "showLyrics") } }
    var compactLyrics: Bool { didSet { store.set(compactLyrics, forKey: "compactLyrics") } }

    // Weather (manual location is used when `weatherUseLocation` is off or Location is denied)
    var weatherEnabled: Bool { didSet { store.set(weatherEnabled, forKey: "weatherEnabled") } }
    var weatherUseLocation: Bool { didSet { store.set(weatherUseLocation, forKey: "weatherUseLocation") } }
    var weatherCity: String { didSet { store.set(weatherCity, forKey: "weatherCity") } }
    var weatherLatitude: Double { didSet { store.set(weatherLatitude, forKey: "weatherLatitude") } }
    var weatherLongitude: Double { didSet { store.set(weatherLongitude, forKey: "weatherLongitude") } }

    /// Extra time zones shown under the Home clock (identifiers, at most three).
    var worldClocks: [String] { didSet { store.set(worldClocks, forKey: "worldClocks") } }

    /// Shelf items older than this are removed (0 = keep forever).
    var shelfExpiryDays: Int { didSet { store.set(shelfExpiryDays, forKey: "shelfExpiryDays") } }

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

    // Meeting mode (v0.4)
    var meetingMode: Bool { didSet { store.set(meetingMode, forKey: "meetingMode") } }
    var mutedWarning: Bool { didSet { store.set(mutedWarning, forKey: "mutedWarning") } }
    /// `MeetingApp.id`s the user excluded from meeting detection.
    var disabledMeetingApps: Set<String> { didSet { store.set(Array(disabledMeetingApps), forKey: "disabledMeetingApps") } }

    // Command bar (v0.4): second global shortcut, Carbon key code + modifier mask
    var commandBarEnabled: Bool { didSet { store.set(commandBarEnabled, forKey: "commandBarEnabled") } }
    var commandHotkeyKeyCode: Int { didSet { store.set(commandHotkeyKeyCode, forKey: "commandHotkeyKeyCode") } }
    var commandHotkeyModifiers: Int { didSet { store.set(commandHotkeyModifiers, forKey: "commandHotkeyModifiers") } }
    var commandHotkeyKeyName: String { didSet { store.set(commandHotkeyKeyName, forKey: "commandHotkeyKeyName") } }
    // Agent Hub (AI coding agents over the local socket)
    var agentHubEnabled: Bool { didSet { store.set(agentHubEnabled, forKey: "agentHubEnabled") } }
    var agentApprovals: Bool { didSet { store.set(agentApprovals, forKey: "agentApprovals") } }
    var agentAutoOpen: Bool { didSet { store.set(agentAutoOpen, forKey: "agentAutoOpen") } }
    /// Seconds an approval waits in the island before the agent shows its own prompt.
    var agentApprovalTimeout: Double { didSet { store.set(agentApprovalTimeout, forKey: "agentApprovalTimeout") } }
    var agentCompact: Bool { didSet { store.set(agentCompact, forKey: "agentCompact") } }
    var agentFinishedAlert: Bool { didSet { store.set(agentFinishedAlert, forKey: "agentFinishedAlert") } }
    var agentNotifications: Bool { didSet { store.set(agentNotifications, forKey: "agentNotifications") } }

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
            "focusActivity": true,
            "privacyIndicators": true,
            "downloadsActivity": false, // reading ~/Downloads asks for permission: opt-in
            "networkActivity": true,
            "airPodsBattery": true,
            "artworkTint": true,
            "openShadow": true,
            "showVisualizer": true,
            "reduceMotion": false,
            "accentPreset": AccentPreset.blinko.rawValue,
            "customAccentHex": "#FF5C94",
            "islandStyle": IslandStyle.classic.rawValue,
            "openCornerRadius": 26.0,
            "closedCornerRadius": 14.0,
            "fontStyle": FontStyle.system.rawValue,
            "showLyrics": true,
            "compactLyrics": false,
            "weatherEnabled": false,
            "weatherUseLocation": true,
            "weatherCity": "",
            "weatherLatitude": 0.0,
            "weatherLongitude": 0.0,
            "worldClocks": [String](),
            "shelfExpiryDays": 0,
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
            "meetingMode": true,
            "mutedWarning": false, // needs microphone access: opt-in
            "disabledMeetingApps": [String](),
            "commandBarEnabled": true,
            "commandHotkeyKeyCode": 49,        // kVK_Space
            "commandHotkeyModifiers": 0x0800,  // optionKey
            "commandHotkeyKeyName": "Space",
            "agentHubEnabled": true,
            "agentApprovals": true,
            "agentAutoOpen": true,
            "agentApprovalTimeout": 90.0,
            "agentCompact": true,
            "agentFinishedAlert": true,
            "agentNotifications": true,
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
        focusActivity = store.bool(forKey: "focusActivity")
        privacyIndicators = store.bool(forKey: "privacyIndicators")
        downloadsActivity = store.bool(forKey: "downloadsActivity")
        networkActivity = store.bool(forKey: "networkActivity")
        airPodsBattery = store.bool(forKey: "airPodsBattery")
        artworkTint = store.bool(forKey: "artworkTint")
        openShadow = store.bool(forKey: "openShadow")
        showVisualizer = store.bool(forKey: "showVisualizer")
        reduceMotion = store.bool(forKey: "reduceMotion")
        accentPreset = AccentPreset(rawValue: store.string(forKey: "accentPreset") ?? "") ?? .blinko
        customAccentHex = store.string(forKey: "customAccentHex") ?? "#FF5C94"
        islandStyle = IslandStyle(rawValue: store.string(forKey: "islandStyle") ?? "") ?? .classic
        openCornerRadius = store.double(forKey: "openCornerRadius")
        closedCornerRadius = store.double(forKey: "closedCornerRadius")
        fontStyle = FontStyle(rawValue: store.string(forKey: "fontStyle") ?? "") ?? .system
        showLyrics = store.bool(forKey: "showLyrics")
        compactLyrics = store.bool(forKey: "compactLyrics")
        weatherEnabled = store.bool(forKey: "weatherEnabled")
        weatherUseLocation = store.bool(forKey: "weatherUseLocation")
        weatherCity = store.string(forKey: "weatherCity") ?? ""
        weatherLatitude = store.double(forKey: "weatherLatitude")
        weatherLongitude = store.double(forKey: "weatherLongitude")
        worldClocks = Array((store.stringArray(forKey: "worldClocks") ?? []).prefix(3))
        shelfExpiryDays = store.integer(forKey: "shelfExpiryDays")
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
        meetingMode = store.bool(forKey: "meetingMode")
        mutedWarning = store.bool(forKey: "mutedWarning")
        disabledMeetingApps = Set(store.stringArray(forKey: "disabledMeetingApps") ?? [])
        commandBarEnabled = store.bool(forKey: "commandBarEnabled")
        commandHotkeyKeyCode = store.integer(forKey: "commandHotkeyKeyCode")
        commandHotkeyModifiers = store.integer(forKey: "commandHotkeyModifiers")
        commandHotkeyKeyName = store.string(forKey: "commandHotkeyKeyName") ?? "Space"
        agentHubEnabled = store.bool(forKey: "agentHubEnabled")
        agentApprovals = store.bool(forKey: "agentApprovals")
        agentAutoOpen = store.bool(forKey: "agentAutoOpen")
        agentApprovalTimeout = store.double(forKey: "agentApprovalTimeout")
        agentCompact = store.bool(forKey: "agentCompact")
        agentFinishedAlert = store.bool(forKey: "agentFinishedAlert")
        agentNotifications = store.bool(forKey: "agentNotifications")
    }
}
