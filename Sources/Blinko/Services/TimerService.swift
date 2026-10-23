import AppKit
import Observation

enum TimerMode: Equatable {
    case countdown, focus, shortBreak, longBreak

    var isPomodoro: Bool { self != .countdown }
    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    var title: String {
        switch self {
        case .countdown: "Timer"
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }
}

/// Countdown timer. State is just dates; views render remaining time with
/// `Text(timerInterval:)` / TimelineView, so there is no ticking timer in the model —
/// only one work item that fires at completion.
@MainActor
@Observable
final class TimerService {
    static let shared = TimerService()

    private(set) var endDate: Date?
    private(set) var startDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var total: TimeInterval = 0
    var label = ""
    private(set) var mode: TimerMode = .countdown
    /// Focus sessions completed in the current cycle of four.
    private(set) var completedFocusSessions = 0

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    @ObservationIgnored private var completion: DispatchWorkItem?

    func remaining(at date: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        total > 0 ? 1 - remaining(at: date) / total : 0
    }

    func start(_ seconds: TimeInterval, label: String = "") {
        mode = .countdown
        completedFocusSessions = 0
        begin(seconds, label: label)
    }

    // MARK: Pomodoro

    func startFocus() {
        mode = .focus
        begin(minutes(for: .focus), label: TimerMode.focus.title)
    }

    /// Ends the current pomodoro session early and moves to the next one.
    func skipSession() {
        guard mode.isPomodoro else { return }
        completion?.cancel()
        advancePomodoro(announce: false)
    }

    private func minutes(for mode: TimerMode) -> TimeInterval {
        let p = Preferences.shared
        let m = switch mode {
        case .focus: p.focusMinutes
        case .shortBreak: p.shortBreakMinutes
        case .longBreak: p.longBreakMinutes
        case .countdown: 0
        }
        return TimeInterval(max(1, m) * 60)
    }

    private func advancePomodoro(announce: Bool) {
        let next: TimerMode
        if mode == .focus {
            completedFocusSessions += 1
            next = completedFocusSessions % 4 == 0 ? .longBreak : .shortBreak
        } else {
            if mode == .longBreak { completedFocusSessions = 0 }
            next = .focus
        }
        mode = next
        let seconds = minutes(for: next)
        if Preferences.shared.autoStartNextSession {
            begin(seconds, label: next.title)
        } else {
            // Park the next session, ready to resume.
            endDate = nil
            startDate = nil
            total = seconds
            label = next.title
            pausedRemaining = seconds
        }
        if announce {
            ActivityCenter.shared.show(.focusSession(title: next.title, isBreak: next.isBreak))
        }
    }

    private func begin(_ seconds: TimeInterval, label: String) {
        total = seconds
        self.label = label
        pausedRemaining = nil
        run(for: seconds)
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        completion?.cancel()
    }

    func resume() {
        guard let remaining = pausedRemaining else { return }
        pausedRemaining = nil
        run(for: remaining)
    }

    func add(_ seconds: TimeInterval) {
        if let p = pausedRemaining { pausedRemaining = p + seconds; total += seconds; return }
        guard let endDate else { return start(seconds) }
        total += seconds
        run(for: endDate.timeIntervalSinceNow + seconds)
    }

    func cancel() {
        mode = .countdown
        completedFocusSessions = 0
        stopClock()
    }

    private func stopClock() {
        completion?.cancel()
        endDate = nil
        startDate = nil
        pausedRemaining = nil
    }

    private func run(for seconds: TimeInterval) {
        startDate = .now
        endDate = Date().addingTimeInterval(seconds)
        completion?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finish() {
        if mode.isPomodoro {
            NSSound(named: mode == .focus ? "Glass" : "Hero")?.play()
            advancePomodoro(announce: true)
            return
        }
        cancel()
        NSSound(named: "Glass")?.play()
        ActivityCenter.shared.show(.timerFinished())
    }
}
