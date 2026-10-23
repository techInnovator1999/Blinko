import AppKit
import EventKit
import Observation

struct AgendaItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    let meetingURL: URL?
    let isReminder: Bool
}

/// Upcoming events + reminders. Refreshes only on EventKit change / day change notifications.
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    private(set) var items: [AgendaItem] = []
    private(set) var authorized = false
    private(set) var denied = false

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        updateAuthorization()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            _ = try? await store.requestFullAccessToReminders()
            updateAuthorization()
            reload()
        }
    }

    private func updateAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = status == .fullAccess
        denied = status == .denied || status == .restricted
    }

    func reload() {
        guard authorized else { items = []; return }
        let now = Date()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!.addingTimeInterval(12 * 3600)
        let predicate = store.predicateForEvents(withStart: cal.startOfDay(for: now), end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { e in
                AgendaItem(id: e.calendarItemIdentifier + "\(e.startDate.timeIntervalSince1970)",
                           title: e.title ?? "Untitled",
                           start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                           color: e.calendar.color ?? .systemBlue,
                           meetingURL: Self.meetingURL(in: e), isReminder: false)
            }
        items = Array(events)

        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        let rp = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        store.fetchReminders(matching: rp) { [weak self] reminders in
            let mapped = (reminders ?? []).prefix(6).compactMap { r -> AgendaItem? in
                guard let due = r.dueDateComponents?.date else { return nil }
                return AgendaItem(id: r.calendarItemIdentifier, title: r.title ?? "Reminder",
                                  start: due, end: due, isAllDay: r.dueDateComponents?.hour == nil,
                                  color: r.calendar.color ?? .systemOrange, meetingURL: nil, isReminder: true)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.items = (self.items.filter { !$0.isReminder } + mapped).sorted { $0.start < $1.start }
            }
        }
    }

    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com", "facetime.apple.com"]

    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, meetingHosts.contains(where: { url.host?.contains($0) == true }) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .first { url in meetingHosts.contains { url.host?.contains($0) == true } }
    }

    /// Design-time state for snapshot rendering.
    func injectPreview(_ items: [AgendaItem]) {
        self.items = items
        authorized = true
    }
}
