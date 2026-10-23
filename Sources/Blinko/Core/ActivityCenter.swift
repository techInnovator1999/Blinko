import Foundation
import Observation

enum BluetoothDeviceKind: Equatable {
    case headphones, keyboard, mouse, trackpad, speaker, generic

    var symbol: String {
        switch self {
        case .headphones: "airpodspro"
        case .keyboard: "keyboard.fill"
        case .mouse: "magicmouse.fill"
        case .trackpad: "rectangle.and.hand.point.up.left.fill"
        case .speaker: "hifispeaker.fill"
        case .generic: "dot.radiowaves.left.and.right"
        }
    }
}

/// Battery levels reported by headphones (AirPods & co.). Any of them may be missing.
struct DeviceBattery: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?

    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && single == nil }
    var hasBuds: Bool { left != nil || right != nil }
}

enum PrivacySensor: Equatable {
    case camera, microphone

    var symbol: String { self == .camera ? "video.fill" : "mic.fill" }
    var title: String { self == .camera ? String(localized: "Camera") : String(localized: "Microphone") }
}

enum NetworkEvent: Equatable {
    case wifi(connected: Bool, ssid: String?)
    case vpn(on: Bool)
    case hotspot(name: String?)
}

/// A transient activity defined by the user (blinko://alert, `blinko alert`) or an agent.
struct CustomAlert: Equatable {
    var title: String
    var body: String?
    /// SF Symbol name.
    var symbol: String
    /// Colour name ("orange", "green"…) or "#RRGGBB".
    var color: String
    var duration: TimeInterval
}

/// Short-lived events that briefly take over the closed island.
enum TransientActivity: Equatable {
    case volume(level: Float, muted: Bool)
    case brightness(level: Float)
    case keyboardBacklight(level: Float)
    case microphone(level: Float, muted: Bool)
    case capsLock(on: Bool)
    case focusSession(title: String, isBreak: Bool)
    case power(level: Int, charging: Bool, pluggedIn: Bool)
    case lowBattery(level: Int)
    case bluetooth(name: String, kind: BluetoothDeviceKind, connected: Bool, battery: DeviceBattery? = nil)
    case shelf(count: Int)
    case timerFinished(label: String = "")
    case nowPlayingChanged
    case focusMode(on: Bool, name: String?, symbol: String?)
    case privacy(sensor: PrivacySensor)
    case network(NetworkEvent)
    case downloadFinished(name: String, url: URL)
    /// Speaking while muted in a call (Meeting mode).
    case mutedWarning
    case custom(CustomAlert)
    case appNotification(MirroredNotification)

    /// Updates of the same kind morph in place instead of re-running the entrance transition.
    enum Kind: Equatable { case hud, capsLock, power, lowBattery, bluetooth, shelf, timer, nowPlaying, focusMode, privacy, network, download, meeting, custom, notification }

    var kind: Kind {
        switch self {
        case .volume, .brightness, .keyboardBacklight, .microphone: .hud
        case .capsLock: .capsLock
        case .focusSession: .timer
        case .power: .power
        case .lowBattery: .lowBattery
        case .bluetooth: .bluetooth
        case .shelf: .shelf
        case .timerFinished: .timer
        case .nowPlayingChanged: .nowPlaying
        case .focusMode: .focusMode
        case .privacy: .privacy
        case .network: .network
        case .downloadFinished: .download
        case .mutedWarning: .meeting
        case .custom: .custom
        case .appNotification: .notification
        }
    }

    var duration: TimeInterval {
        if case .custom(let alert) = self { return alert.duration }
        return switch kind {
        case .hud: 1.6
        case .capsLock: 1.3
        case .power, .focusMode, .privacy, .network: 2.6
        case .bluetooth: 3.2
        case .lowBattery: 4
        case .shelf: 1.8
        case .timer: 6
        case .nowPlaying: 2.2
        case .download: 5
        case .meeting: 4
        case .custom: 3
        case .notification: 6.5
        }
    }
}

/// Global queue for transient activities (shared across all displays).
/// Uses a single cancellable work item — no repeating timers.
@MainActor
@Observable
final class ActivityCenter {
    static let shared = ActivityCenter()

    private(set) var current: TransientActivity?

    @ObservationIgnored private var dismissWork: DispatchWorkItem?

    /// How long the current activity stays (its default, or a shorter priority interruption).
    private(set) var currentDuration: TimeInterval = 0
    /// Alerts that arrived while a message card was up; they show right after it.
    @ObservationIgnored private var queued: [TransientActivity] = []

    func show(_ activity: TransientActivity, duration: TimeInterval? = nil) {
        // A message card (Slack…) has priority: other alerts wait their turn instead of
        // replacing it. User-driven HUDs (volume, brightness…) and newer messages still win.
        if case .appNotification = current, !activity.isUserDriven, activity.kind != .notification {
            if queued.count < 3, !queued.contains(activity) { queued.append(activity) }
            return
        }
        if current?.kind != activity.kind, let event = activity.soundEvent { SoundService.shared.play(event) }
        if current != activity { current = activity }
        currentDuration = duration ?? activity.duration
        scheduleDismiss(after: currentDuration)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishCurrent() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finishCurrent() {
        current = nil
        if !queued.isEmpty { show(queued.removeFirst()) }
    }

    /// Pauses the auto-dismiss while the pointer rests on the activity; resumes briefly after.
    func hold(_ on: Bool) {
        dismissWork?.cancel()
        guard !on, current != nil else { return }
        scheduleDismiss(after: 2.5)
    }

    func dismiss() {
        dismissWork?.cancel()
        current = nil
    }
}

extension TransientActivity {
    /// Sound for activities raised by system events. Timers, Focus and agents play their
    /// sounds where they happen (they know more, e.g. start vs. end).
    var soundEvent: SoundEvent? {
        switch self {
        case .mutedWarning: .meetingMuted
        case .lowBattery: .lowBattery
        case .power(_, _, let pluggedIn): pluggedIn ? .chargerConnected : nil
        case .bluetooth(_, _, let connected, _): connected ? .deviceConnected : nil
        case .downloadFinished: .downloadFinished
        case .shelf: .shelfAdded
        default: nil
        }
    }
}

extension TransientActivity {
    /// Pressed by the user right now (keys, gestures): always shown immediately.
    var isUserDriven: Bool {
        switch self {
        case .volume, .brightness, .keyboardBacklight, .microphone, .capsLock: true
        default: false
        }
    }
}
