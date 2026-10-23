import AppKit
import Observation

/// Blinko's own notification sounds (Resources/Sounds, synthesized by
/// design/sounds/make_sounds.py): deep, bass-rich and loudness-matched.
enum NotificationSound: String, CaseIterable, Identifiable, Codable {
    case blink, pulse, bloom, orbit, drop, halo, tap, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .blink: String(localized: "Blink")
        case .pulse: String(localized: "Pulse")
        case .bloom: String(localized: "Bloom")
        case .orbit: String(localized: "Orbit")
        case .drop: String(localized: "Drop")
        case .halo: String(localized: "Halo")
        case .tap: String(localized: "Tap")
        case .none: String(localized: "None")
        }
    }
}

/// Every moment that can make a sound, each with its own switch and sound.
enum SoundEvent: String, CaseIterable, Identifiable {
    case timerStart, timerEnd, focusSession
    case agentApproval, agentFinished, agentNotification
    case meetingMuted
    case lowBattery, chargerConnected
    case deviceConnected, downloadFinished, shelfAdded
    case customAlert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timerStart: String(localized: "Timer or focus starts")
        case .timerEnd: String(localized: "Timer ends")
        case .focusSession: String(localized: "Focus session changes (work ↔ break)")
        case .agentApproval: String(localized: "AI agent needs your permission")
        case .agentFinished: String(localized: "AI agent finished a task")
        case .agentNotification: String(localized: "AI agent notification")
        case .meetingMuted: String(localized: "You're talking while muted")
        case .lowBattery: String(localized: "Low battery")
        case .chargerConnected: String(localized: "Charger connected")
        case .deviceConnected: String(localized: "Bluetooth device connects")
        case .downloadFinished: String(localized: "Download finished")
        case .shelfAdded: String(localized: "File added to Shelf")
        case .customAlert: String(localized: "Alerts from Shortcuts, URL scheme or CLI")
        }
    }

    var group: String {
        switch self {
        case .timerStart, .timerEnd, .focusSession: String(localized: "Timers & Focus")
        case .agentApproval, .agentFinished, .agentNotification: String(localized: "AI Agents")
        case .meetingMuted: String(localized: "Meetings")
        case .lowBattery, .chargerConnected: String(localized: "Power")
        case .deviceConnected, .downloadFinished, .shelfAdded, .customAlert: String(localized: "Other")
        }
    }

    var defaultSound: NotificationSound {
        switch self {
        case .timerStart, .shelfAdded, .chargerConnected, .deviceConnected: .tap
        case .timerEnd: .bloom
        case .focusSession: .halo
        case .agentApproval, .customAlert: .blink
        case .agentFinished: .orbit
        case .agentNotification: .tap
        case .meetingMuted: .pulse
        case .lowBattery, .downloadFinished: .drop
        }
    }

    var enabledByDefault: Bool {
        switch self {
        case .timerStart, .timerEnd, .focusSession, .agentApproval, .agentFinished, .meetingMuted, .lowBattery, .customAlert: true
        case .agentNotification, .chargerConnected, .deviceConnected, .downloadFinished, .shelfAdded: false
        }
    }

    /// Urgent events still sound during Focus (you asked to be interrupted for these).
    var bypassesFocus: Bool { self == .agentApproval || self == .meetingMuted || self == .lowBattery }
}

/// Plays event sounds. Each file is decoded once and cached; nothing runs between sounds.
@MainActor
@Observable
final class SoundService {
    static let shared = SoundService()

    @ObservationIgnored private var cache: [NotificationSound: NSSound] = [:]
    @ObservationIgnored private var lastPlayed = Date.distantPast

    func play(_ event: SoundEvent) {
        let prefs = Preferences.shared
        guard prefs.soundsEnabled, prefs.isSoundOn(event) else { return }
        if prefs.silenceSoundsInFocus, !event.bypassesFocus, FocusService.shared.isFocused { return }
        // Collapse bursts (e.g. several alerts at once) into one sound.
        guard Date().timeIntervalSince(lastPlayed) > 0.35 else { return }
        lastPlayed = Date()
        play(prefs.sound(for: event), volume: Float(prefs.soundVolume))
    }

    /// Settings preview: always plays, ignores switches.
    func preview(_ sound: NotificationSound) {
        play(sound, volume: Float(Preferences.shared.soundVolume))
    }

    private func play(_ sound: NotificationSound, volume: Float) {
        guard sound != .none, let player = player(for: sound) else { return }
        player.stop()
        player.volume = volume
        player.play()
    }

    private func player(for sound: NotificationSound) -> NSSound? {
        if let cached = cache[sound] { return cached }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"),
              let player = NSSound(contentsOf: url, byReference: true) else { return nil }
        cache[sound] = player
        return player
    }
}
