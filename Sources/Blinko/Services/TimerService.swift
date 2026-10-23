import AppKit
import Observation

enum TimerMode: Equatable {
    /// No Pomodoro session (countdowns live in `TimerService.timers`).
    case countdown
    case focus, shortBreak, longBreak

    var isPomodoro: Bool { self != .countdown }
    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    var title: String {
        switch self {
        case .countdown: String(localized: "Timer")
        case .focus: String(localized: "Focus")
        case .shortBreak: String(localized: "Short Break")
        case .longBreak: String(localized: "Long Break")
        }
    }
}

/// One of several concurrent countdowns. Just dates, like the Pomodoro session.
struct CountdownTimer: Identifiable, Equatable {
    let id = UUID()
    var label: String
    var total: TimeInterval
    var endDate: Date?
    var pausedRemaining: TimeInterval?

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        total > 0 ? 1 - remaining(at: date) / total : 0
    }
}

/// Countdown timers plus one Pomodoro session. State is just dates; views render remaining
/// time with `Text(timerInterval:)` / TimelineView, so there is no ticking timer in the
/// model — only one work item per timer that fires at completion.
@MainActor
@Observable
final class TimerService {
    static let shared = TimerService()

    // Pomodoro session
    private(set) var endDate: Date?
    private(set) var startDate: Date?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var total: TimeInterval = 0
    var label = ""
    private(set) var mode: TimerMode = .countdown
    /// Focus sessions completed in the current cycle of four.
    private(set) var completedFocusSessions = 0

    /// Concurrent countdowns, in the order they were started.
    private(set) var timers: [CountdownTimer] = []
    static let maxTimers = 6

    /// Pomodoro session state.
    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    /// Anything counting down (drives the compact timer).
    var hasRunning: Bool { isRunning || timers.contains(where: \.isRunning) }

    /// The running timer that ends first: what the closed island shows.
    var soonest: (end: Date, mode: TimerMode)? {
        var ends: [(Date, TimerMode)] = timers.compactMap { $0.endDate.map { ($0, .countdown) } }
        if let endDate { ends.append((endDate, mode)) }
        return ends.min { $0.0 < $1.0 }.map { (end: $0.0, mode: $0.1) }
    }

    /// Running timers besides the soonest one ("+N" badge).
    var othersRunning: Int { max(0, timers.filter(\.isRunning).count + (isRunning ? 1 : 0) - 1) }

    /// The countdown the Timer tab's ring follows: the running one ending first, else the latest.
    var featured: CountdownTimer? {
        timers.filter(\.isRunning).min { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) } ?? timers.last
    }

    @ObservationIgnored private var completion: DispatchWorkItem?
    @ObservationIgnored private var completions: [UUID: DispatchWorkItem] = [:]

    func remaining(at date: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        total > 0 ? 1 - remaining(at: date) / total : 0
    }

    // MARK: Countdowns

    /// Starts a new countdown alongside any that are already running.
    func start(_ seconds: TimeInterval, label: String = "") {
        if timers.count >= Self.maxTimers, let oldest = timers.first { cancel(oldest.id) }
        let timer = CountdownTimer(label: label, total: seconds)
        timers.append(timer)
        run(timer.id, for: seconds)
        SoundService.shared.play(.timerStart)
    }

    func pause(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), let end = timers[i].endDate else { return }
        timers[i].pausedRemaining = max(0, end.timeIntervalSinceNow)
        timers[i].endDate = nil
        completions.removeValue(forKey: id)?.cancel()
    }

    func resume(_ id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }), let remaining = timers[i].pausedRemaining else { return }
        timers[i].pausedRemaining = nil
        run(id, for: remaining)
    }

    func add(_ seconds: TimeInterval, to id: UUID) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[i].total += seconds
        if let p = timers[i].pausedRemaining {
            timers[i].pausedRemaining = p + seconds
        } else if let end = timers[i].endDate {
            run(id, for: end.timeIntervalSinceNow + seconds)
        }
    }

    func cancel(_ id: UUID) {
        completions.removeValue(forKey: id)?.cancel()
        timers.removeAll { $0.id == id }
    }

    func cancelAllCountdowns() {
        completions.values.forEach { $0.cancel() }
        completions.removeAll()
        timers.removeAll()
    }

    private func run(_ id: UUID, for seconds: TimeInterval) {
        guard let i = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[i].endDate = Date().addingTimeInterval(seconds)
        completions[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishCountdown(id) }
        completions[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finishCountdown(_ id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        cancel(id)
        SoundService.shared.play(.timerEnd)
        ActivityCenter.shared.show(.timerFinished(label: timer.label))
    }

    // MARK: Pomodoro

    func startFocus() {
        mode = .focus
        begin(minutes(for: .focus), label: TimerMode.focus.title)
        SoundService.shared.play(.timerStart)
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
        runSession(for: seconds)
    }

    /// Pauses the Pomodoro session.
    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        completion?.cancel()
    }

    func resume() {
        guard let remaining = pausedRemaining else { return }
        pausedRemaining = nil
        runSession(for: remaining)
    }

    /// Stops the Pomodoro session.
    func cancel() {
        mode = .countdown
        completedFocusSessions = 0
        completion?.cancel()
        endDate = nil
        startDate = nil
        pausedRemaining = nil
    }

    private func runSession(for seconds: TimeInterval) {
        startDate = .now
        endDate = Date().addingTimeInterval(seconds)
        completion?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishSession() }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finishSession() {
        guard mode.isPomodoro else { return }
        SoundService.shared.play(.focusSession)
        advancePomodoro(announce: true)
    }
}
