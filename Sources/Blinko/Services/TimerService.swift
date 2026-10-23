import AppKit
import Observation

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
        completion?.cancel()
        endDate = nil
        startDate = nil
        pausedRemaining = nil
    }

    private func run(for seconds: TimeInterval) {
        startDate = startDate ?? .now
        endDate = Date().addingTimeInterval(seconds)
        completion?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finish() {
        cancel()
        NSSound(named: "Glass")?.play()
        ActivityCenter.shared.show(.timerFinished)
    }
}
