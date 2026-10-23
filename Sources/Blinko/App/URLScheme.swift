import AppKit
import os

private let log = Logger(subsystem: "app.blinko.Blinko", category: "automation")

/// App-level routing into the islands, for things that don't start from an island
/// (URL scheme, CLI, Agent Hub). Requests that arrive before the islands exist (a URL
/// that launched Blinko) are queued until `attach`.
@MainActor
final class AppRouter {
    static let shared = AppRouter()

    private weak var manager: NotchManager?
    private var pending: [() -> Void] = []
    /// The island the Agent Hub opened by itself (closed again once approvals are answered).
    private weak var autoOpened: NotchViewModel?

    func attach(_ manager: NotchManager) {
        self.manager = manager
        let queued = pending
        pending.removeAll()
        queued.forEach { $0() }
    }

    private func whenReady(_ block: @escaping () -> Void) {
        if manager != nil { block() } else { pending.append(block) }
    }

    /// True while any island is open (e.g. an approval card is up).
    var anyIslandOpen: Bool { manager?.viewModels.contains { $0.isOpen } ?? false }

    /// The island on the display under the pointer.
    private var activeIsland: NotchViewModel? {
        let models = manager?.viewModels ?? []
        let mouse = NSEvent.mouseLocation
        return models.first { $0.geometry.screenFrame.contains(mouse) } ?? models.first
    }

    func open(tab: NotchTab?) {
        whenReady { [weak self] in
            guard let self, let manager = self.manager else { return }
            if let tab { manager.open(tab: tab) } else { manager.toggleOnActiveScreen() }
        }
    }

    // MARK: Agent Hub

    /// A permission request arrived: open the island on the Agents tab, unless the user is
    /// already working in it (an open island on another tab is left alone; the closed
    /// island's waiting state and the badge still show).
    func presentApproval() {
        whenReady { [weak self] in
            guard let self, let vm = self.activeIsland else { return }
            if vm.isOpen {
                if vm.tab != .agents, !vm.holdsOpen { vm.tab = .agents }
                return
            }
            vm.open(tab: .agents)
            self.autoOpened = vm
        }
    }

    /// Every approval is answered: close the island again if Blinko opened it by itself and
    /// the pointer isn't on it.
    func approvalsCleared() {
        guard let vm = autoOpened else { return }
        autoOpened = nil
        if vm.isOpen, !vm.isHovering, !vm.isPinned { vm.close() }
    }
}

// MARK: - blinko:// URL scheme

/// `blinko://` actions (Shortcuts "Open URL", scripts, the `blinko` CLI):
///   open?tab=shelf · alert?title=&body=&icon=&color=&duration= · timer?minutes=&label=
///   focus/start · focus/stop · shelf/add?path=… · keepawake?minutes= (none = until stopped, off=1 stops)
/// Parameters are only ever used as data (text, numbers, existing file paths): nothing is executed.
@MainActor
enum URLSchemeHandler {
    static func install() {
        NSAppleEventManager.shared().setEventHandler(
            Handler.shared, andSelector: #selector(Handler.handle(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    final class Handler: NSObject {
        static let shared = Handler()

        @objc func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
            guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
                  let url = URL(string: string) else { return }
            MainActor.assumeIsolated { _ = URLSchemeHandler.perform(url) }
        }
    }

    /// Returns false for unknown actions.
    @discardableResult
    static func perform(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "blinko" else { return false }
        let action = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" })
            .filter { !$0.isEmpty }.joined(separator: "/").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        func number(_ name: String) -> Double? { value(name).flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil } }
        log.info("url action \(action, privacy: .public)")

        switch action {
        case "open", "":
            AppRouter.shared.open(tab: value("tab").flatMap { NotchTab(rawValue: $0.lowercased()) })
        case "alert", "notify":
            let title = (value("title") ?? value("text") ?? "Blinko").agentSafe(80)
            let alert = CustomAlert(title: title, body: value("body").map { $0.agentSafe(120) },
                                    symbol: AlertStyle.validSymbol(value("icon")),
                                    color: value("color") ?? "white",
                                    duration: min(max(number("duration") ?? 4, 1), 30))
            ActivityCenter.shared.show(.custom(alert))
            SoundService.shared.play(.customAlert)
        case "timer":
            let seconds = number("seconds") ?? (number("minutes") ?? 5) * 60
            guard seconds >= 1, seconds <= 24 * 3600 else { return false }
            TimerService.shared.start(seconds, label: value("label")?.agentSafe(40) ?? Format.duration(seconds))
        case "focus/start", "focus":
            TimerService.shared.startFocus()
        case "focus/stop":
            TimerService.shared.cancel()
        case "shelf/add":
            let urls = items.filter { $0.name.lowercased() == "path" }.compactMap(\.value)
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return false }
            ShelfService.shared.add(urls)
        case "keepawake":
            if value("off") != nil || value("minutes") == "0" {
                KeepAwakeService.shared.stop()
            } else {
                KeepAwakeService.shared.start(for: number("minutes").map { min(max($0, 1), 24 * 60) * 60 })
            }
        default:
            log.error("unknown blinko:// action \(action, privacy: .public)")
            return false
        }
        return true
    }
}

extension AppDelegate {
    /// Registered before launch finishes so the URL that launched Blinko is delivered too.
    func applicationWillFinishLaunching(_ notification: Notification) {
        URLSchemeHandler.install()
    }
}

private extension String {
    /// Single line, trimmed, at most `limit` characters.
    func agentSafe(_ limit: Int) -> String {
        let line = components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}
