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
    case bluetooth(name: String, kind: BluetoothDeviceKind, connected: Bool)
    case shelf(count: Int)
    case timerFinished
    case nowPlayingChanged

    /// Updates of the same kind morph in place instead of re-running the entrance transition.
    enum Kind: Equatable { case hud, capsLock, power, lowBattery, bluetooth, shelf, timer, nowPlaying }

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
        }
    }

    var duration: TimeInterval {
        switch kind {
        case .hud: 1.6
        case .capsLock: 1.3
        case .power, .bluetooth: 2.6
        case .lowBattery: 4
        case .shelf: 1.8
        case .timer: 6
        case .nowPlaying: 2.2
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

    func show(_ activity: TransientActivity) {
        if current != activity { current = activity }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.current = nil }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + activity.duration, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        current = nil
    }
}
