import AppKit
import Intents
import Observation

/// Focus / Do Not Disturb state.
///
/// Best source: `~/Library/DoNotDisturb/DB` (needs Full Disk Access). It names the active
/// mode, and a DispatchSource on the directory makes it fully event-driven. Without that,
/// `INFocusStatusCenter` (user-authorized) tells on/off only. It has no change
/// notification for a regular app, so it is re-read on app switches and screen wake, plus
/// one slow tolerant timer. Turned off, or not authorized: no work at all.
@MainActor
@Observable
final class FocusService {
    static let shared = FocusService()

    private(set) var isFocused = false
    private(set) var modeName: String?
    private(set) var modeSymbol: String?
    private(set) var authorization = INFocusStatusCenter.default.authorizationStatus
    /// True when the Focus database is readable (Full Disk Access): mode names available.
    private(set) var readsDatabase = false

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var running = false
    @ObservationIgnored private var debounce: DispatchWorkItem?
    @ObservationIgnored private let queue = DispatchQueue(label: "app.blinko.focus", qos: .utility)

    private nonisolated static let dbDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)

    func refresh() {
        Preferences.shared.focusActivity ? start() : stop()
    }

    func requestAuthorization() {
        INFocusStatusCenter.default.requestAuthorization { status in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.authorization = status
                    self.stop()
                    self.refresh()
                }
            }
        }
    }

    /// Picks up access granted while running (Settings re-checks when shown).
    func recheckAccess() {
        authorization = INFocusStatusCenter.default.authorizationStatus
        guard Preferences.shared.focusActivity, !readsDatabase else { return }
        stop()
        start()
    }

    private func start() {
        guard !running else { return }
        authorization = INFocusStatusCenter.default.authorizationStatus
        if let state = Self.readDatabase() {
            running = true
            readsDatabase = true
            apply(state, announce: false)
            watchDatabase()
        } else if authorization == .authorized {
            running = true
            readsDatabase = false
            apply(Self.readStatusCenter(), announce: false)
            watchStatusCenter()
        }
    }

    private func stop() {
        running = false
        source?.cancel()
        source = nil
        timer?.invalidate()
        timer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: Sources

    private func watchDatabase() {
        let fd = open(Self.dbDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        // The JSON files are replaced atomically, which shows up as a write to the directory.
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        src.setEventHandler { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleRead() } }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleRead() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.queue.async {
                let state = Self.readDatabase()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if let state { self?.apply(state, announce: true) } }
                }
            }
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func watchStatusCenter() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply(Self.readStatusCenter(), announce: true) }
            })
        }
        // No change event exists for this API: one slow, heavily coalesced check.
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(Self.readStatusCenter(), announce: true) }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: State

    struct State: Equatable {
        var focused: Bool
        var name: String?
        var symbol: String?
    }

    private func apply(_ state: State, announce: Bool) {
        let changed = state.focused != isFocused || (state.focused && state.name != modeName)
        isFocused = state.focused
        modeName = state.name
        modeSymbol = state.symbol
        guard changed, announce, Preferences.shared.focusActivity else { return }
        ActivityCenter.shared.show(.focusMode(on: state.focused, name: state.name, symbol: state.symbol))
    }

    private nonisolated static func readStatusCenter() -> State {
        State(focused: INFocusStatusCenter.default.focusStatus.isFocused ?? false, name: nil, symbol: nil)
    }

    /// Parses the Focus database. Returns nil when it is unreadable (no Full Disk Access).
    private nonisolated static func readDatabase() -> State? {
        guard let data = try? Data(contentsOf: dbDirectory.appendingPathComponent("Assertions.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let records = (json["data"] as? [[String: Any]])?.first?["storeAssertionRecords"] as? [[String: Any]] ?? []
        guard let details = records.last?["assertionDetails"] as? [String: Any],
              let modeID = details["assertionDetailsModeIdentifier"] as? String
        else { return State(focused: false) }

        var name: String?
        var symbol: String?
        if let modes = try? Data(contentsOf: dbDirectory.appendingPathComponent("ModeConfigurations.json")),
           let config = try? JSONSerialization.jsonObject(with: modes) as? [String: Any],
           let all = (config["data"] as? [[String: Any]])?.first?["modeConfigurations"] as? [String: Any],
           let mode = (all[modeID] as? [String: Any])?["mode"] as? [String: Any] {
            name = mode["name"] as? String
            symbol = mode["symbolImageName"] as? String
        }
        return State(focused: true, name: name, symbol: symbol)
    }
}
