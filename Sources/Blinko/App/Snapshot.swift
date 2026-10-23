import AppKit
import SwiftUI

/// `Blinko --snapshot <dir>` renders every island state to PNG for design review,
/// without starting services or touching the menu bar.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !args.contains("--themes-only") { render(to: dir) }
        renderThemes(to: dir)
        return true
    }

    private static func render(to dir: URL) {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        NowPlayingService.shared.injectPreview(title: "Midnight City", artist: "M83",
                                               duration: 243, elapsed: 97, playing: true,
                                               artwork: sampleArtwork())

        func shot(_ name: String, height: CGFloat = 280, setup: (NotchViewModel) -> Void) {
            let vm = NotchViewModel(geometry: geometry)
            setup(vm)
            let canvas = CGSize(width: max(760, vm.canvasSize.width + 40), height: height)
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.75, green: 0.55, blue: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                NotchRootView(vm: vm).frame(width: canvas.width, height: canvas.height)
            }
            .frame(width: canvas.width, height: canvas.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        }

        shot("01-closed-music") { _ in }
        shot("02-hud-volume") { _ in ActivityCenter.shared.show(.volume(level: 0.62, muted: false)) }
        shot("03-charging") { _ in ActivityCenter.shared.show(.power(level: 76, charging: true, pluggedIn: true)) }
        shot("04-bluetooth") { _ in ActivityCenter.shared.show(.bluetooth(name: "AirPods Pro", kind: .headphones, connected: true)) }
        shot("05-capslock") { _ in ActivityCenter.shared.show(.capsLock(on: true)) }
        shot("06-mic") { _ in ActivityCenter.shared.show(.microphone(level: 0.4, muted: false)) }
        shot("07-focus") { _ in ActivityCenter.shared.show(.focusSession(title: "Short Break", isBreak: true)) }
        // v0.3 awareness activities
        let airpods = DeviceBattery(left: 82, right: 76, caseLevel: 54)
        shot("11-airpods-battery") { _ in ActivityCenter.shared.show(.bluetooth(name: "AirPods Pro", kind: .headphones, connected: true, battery: airpods)) }
        shot("12-focus-mode") { _ in ActivityCenter.shared.show(.focusMode(on: true, name: "Do Not Disturb", symbol: "moon.fill")) }
        shot("12b-focus-off") { _ in ActivityCenter.shared.show(.focusMode(on: false, name: nil, symbol: nil)) }
        shot("13-privacy-camera") { _ in ActivityCenter.shared.show(.privacy(sensor: .camera)) }
        shot("14-wifi") { _ in ActivityCenter.shared.show(.network(.wifi(connected: true, ssid: "Studio 5G"))) }
        shot("14b-vpn") { _ in ActivityCenter.shared.show(.network(.vpn(on: true))) }
        shot("14c-hotspot") { _ in ActivityCenter.shared.show(.network(.hotspot(name: "iPhone"))) }
        let downloaded = URL(fileURLWithPath: "/tmp/Blinko-0.3.0.dmg")
        shot("15-download-finished") { _ in ActivityCenter.shared.show(.downloadFinished(name: downloaded.lastPathComponent, url: downloaded)) }
        ActivityCenter.shared.dismiss()
        PrivacyService.shared.injectPreview(camera: true, mic: true)
        shot("16-privacy-over-music") { _ in }
        DownloadsService.shared.injectPreview(.init(name: "Xcode.xip", received: 1_200_000_000, total: 3_000_000_000), count: 2)
        shot("17-download-progress") { _ in }
        DownloadsService.shared.injectPreview(.init(name: "video.mp4", received: 48_500_000, total: nil))
        shot("17b-download-indeterminate") { _ in }
        DownloadsService.shared.injectPreview(nil, recent: downloaded)
        let idleClock = Preferences.shared.showClockWhenIdle
        let np = NowPlayingService.shared
        np.injectPreview(title: np.title, artist: np.artist, duration: np.duration, elapsed: 97, playing: false, artwork: np.artwork)
        shot("16b-privacy-idle") { _ in }
        PrivacyService.shared.injectPreview(camera: false, mic: false)
        Preferences.shared.showClockWhenIdle = true
        shot("09-idle-clock") { _ in }
        Preferences.shared.showClockWhenIdle = idleClock
        np.injectPreview(title: np.title, artist: np.artist, duration: np.duration, elapsed: 97, playing: true, artwork: np.artwork)
        TimerService.shared.startFocus()
        shot("08-compact-focus") { _ in }
        for tab in NotchTab.allCases {
            shot("10-open-\(tab.rawValue)") { vm in vm.open(tab: tab) }
        }
        // Several countdowns: the closed island shows the soonest with a "+N" badge.
        let timers = TimerService.shared
        timers.cancel()
        timers.start(300, label: Format.duration(300))
        timers.start(1500, label: Format.duration(1500))
        timers.start(3600, label: Format.duration(3600))
        if let last = timers.timers.last { timers.pause(last.id) }
        shot("18-compact-timers") { _ in }
        shot("18b-open-timers") { vm in vm.open(tab: .timer) }
        timers.cancelAllCountdowns()

        // Weather + world clocks on Home, weather in the header elsewhere.
        let prefs = Preferences.shared
        let saved = (prefs.weatherEnabled, prefs.worldClocks)
        let hour = Calendar.current.dateInterval(of: .hour, for: .now)!.start
        let codes = [2, 3, 61, 3, 1]
        WeatherService.shared.injectPreview(.init(
            temperature: 18.4, code: 2, isDay: true, high: 21, low: 12,
            hours: (1...5).map { i in .init(date: hour.addingTimeInterval(Double(i) * 3600), temperature: 18 + Double(i % 3),
                                             code: codes[i - 1], isDay: true) },
            place: "Brussels", fetchedAt: .now))
        prefs.weatherEnabled = true
        prefs.worldClocks = ["America/New_York", "Asia/Tokyo", "Europe/London"]
        shot("19-open-home-weather") { vm in vm.open(tab: .home) }
        shot("19b-header-weather") { vm in vm.open(tab: .stats) }
        prefs.weatherEnabled = saved.0
        prefs.worldClocks = saved.1

        // Synced lyrics: player line + closed-island wing. Line 3 is current at 1:37.
        let lrc = "[01:20.00] First placeholder line\n[01:28.50] Second placeholder line\n[01:35.00] Neon lights over a sleeping town tonight\n[01:44.00] Fourth placeholder line"
        LyricsService.shared.injectPreview(key: LyricsService.key(title: np.title, artist: np.artist), lrc: lrc)
        let compactLyrics = prefs.compactLyrics
        prefs.compactLyrics = true
        shot("20-compact-lyrics") { _ in }
        shot("20b-open-lyrics") { vm in vm.open(tab: .home) }
        prefs.compactLyrics = compactLyrics

        // Notes + Tools tabs with sample content.
        NotesService.shared.injectPreview(
            text: "Call Sam about the launch deck\n— ship v0.3 build to beta testers\n— renew domain before Friday",
            snippets: ["hello@blinko.app", "https://github.com/techInnovator1999/Blinko", "Thanks — talk soon!"])
        ColorPickerService.shared.injectPreview(["#FF5A5F", "#3A7BFF", "#34C759", "#FFD60A", "#AF52DE", "#1C1C1E"])
        KeepAwakeService.shared.injectPreview(until: Date().addingTimeInterval(3600))
        shot("21-open-notes") { vm in vm.open(tab: .notes) }
        shot("21b-open-tools") { vm in vm.open(tab: .tools) }

        // Busiest header a MacBook can show: 7 tabs, Keep Awake, weather, time, battery.
        BatteryService.shared.injectPreview(level: 84, pluggedIn: false)
        prefs.weatherEnabled = true
        shot("22-header-full") { vm in vm.open(tab: .stats) }
        prefs.weatherEnabled = saved.0

        // v0.4 Agent Hub: working, several sessions, approval, empty tab; custom alerts.
        ActivityCenter.shared.dismiss()
        TimerService.shared.cancel()
        np.injectPreview(title: np.title, artist: np.artist, duration: np.duration, elapsed: 97, playing: false, artwork: np.artwork)
        AgentSpinner.renderStatic = true
        let hub = AgentHubService.shared
        let now = Date()
        let blinko = AgentSession(id: "claude-code:1", agent: "claude-code", cwd: "/Users/me/Projects/blinko", title: nil,
                                  state: .working, detail: "Bash · swift build -c release", tool: "Bash",
                                  startedAt: now - 900, updatedAt: now, stateSince: now - 260)
        let site = AgentSession(id: "codex:2", agent: "codex", cwd: "/Users/me/Projects/website", title: nil,
                                state: .working, detail: "Edit · src/pages/index.tsx", tool: "Edit",
                                startedAt: now - 1800, updatedAt: now, stateSince: now - 75)
        let api = AgentSession(id: "claude-code:3", agent: "claude-code", cwd: "/Users/me/Projects/api-server", title: nil,
                               state: .idle, detail: "Finished · all 214 tests pass", tool: nil,
                               startedAt: now - 5400, updatedAt: now - 600, stateSince: now - 600, cost: 0.84)
        hub.injectPreview(sessions: [blinko], approvals: [])
        shot("23-compact-agent-working") { _ in }
        hub.injectPreview(sessions: [blinko, site, api], approvals: [])
        shot("23b-compact-agents-multiple") { _ in }
        shot("24-open-agents") { vm in vm.open(tab: .agents) }
        var waiting = blinko
        waiting.state = .waiting
        let approval = AgentApproval(id: "r1", sessionID: blinko.id, connection: 0, agent: "claude-code", project: "blinko",
                                     tool: "Bash", summary: "rm -rf .build && swift build -c release --arch arm64 --arch x86_64",
                                     detail: "Clean rebuild of the universal binary", receivedAt: now, deadline: now + 72)
        hub.injectPreview(sessions: [waiting, site, api], approvals: [approval])
        shot("25-compact-agent-approval") { _ in }
        shot("25b-open-approval") { vm in vm.open(tab: .agents) }
        var second = approval
        second = AgentApproval(id: "r2", sessionID: site.id, connection: 0, agent: "codex", project: "website", tool: "Edit",
                               summary: "~/Projects/website/src/pages/index.tsx", detail: "−12 +31 lines",
                               receivedAt: now, deadline: now + 80)
        hub.injectPreview(sessions: [waiting, site, api], approvals: [approval, second])
        shot("25c-open-approval-queue") { vm in vm.open(tab: .agents) }
        hub.injectPreview(sessions: [], approvals: [])
        shot("26-open-agents-empty") { vm in vm.open(tab: .agents) }
        shot("27-custom-alert") { _ in
            ActivityCenter.shared.show(.custom(CustomAlert(title: "Build passed", body: "blinko · 42 s",
                                                           symbol: "checkmark.seal.fill", color: "green", duration: 4)))
        }
        shot("27b-custom-alert-title") { _ in
            ActivityCenter.shared.show(.custom(CustomAlert(title: "Stand up", body: nil, symbol: "figure.walk",
                                                           color: "#FF9F0A", duration: 4)))
        }
        shot("27c-agent-finished") { _ in
            ActivityCenter.shared.show(.custom(CustomAlert(title: "api-server", body: "Finished", symbol: "checkmark.circle.fill",
                                                           color: "green", duration: 3)))
        }
        ActivityCenter.shared.dismiss()
        renderV04(shot: shot)
    }

    /// v0.4: Meeting mode and the command bar.
    private static func renderV04(shot: (String, CGFloat, (NotchViewModel) -> Void) -> Void) {
        let prefs = Preferences.shared
        let meetingMode = prefs.meetingMode
        prefs.meetingMode = true
        NowPlayingService.shared.injectPreview(title: "", artist: "", duration: 0, elapsed: 0, playing: false, artwork: nil)
        PrivacyService.shared.injectPreview(camera: false, mic: true)
        let meeting = MeetingService.shared
        meeting.injectPreview(app: "facetime", started: Date().addingTimeInterval(-754))
        shot("30-meeting-compact", 280) { _ in }
        PrivacyService.shared.injectPreview(camera: true, mic: true)
        meeting.injectPreview(app: "facetime", started: Date().addingTimeInterval(-3_725), micMuted: true)
        shot("30b-meeting-compact-camera-muted", 280) { _ in }
        meeting.injectPreview(app: "facetime", started: Date().addingTimeInterval(-754))
        shot("31-meeting-card", 280) { vm in vm.open(tab: .home) }
        meeting.injectPreview(app: "teams", started: Date().addingTimeInterval(-1_312), micMuted: false, appMuted: true)
        shot("31b-meeting-card-app-muted", 280) { vm in vm.open(tab: .home) }
        ActivityCenter.shared.show(.mutedWarning)
        shot("32-muted-warning", 280) { _ in }
        ActivityCenter.shared.dismiss()
        meeting.injectPreview(app: nil)
        PrivacyService.shared.injectPreview(camera: false, mic: false)
        prefs.meetingMode = meetingMode

        // Command bar: one shot per kind of result.
        AppIndex.shared.injectPreview()
        ShortcutsIndex.shared.injectPreview(["Start Work Day", "Shorten URL", "Make GIF", "Send Location to Sam"])
        CurrencyRates.shared.injectPreview(["USD": 1, "EUR": 0.92, "GBP": 0.79, "JPY": 151.2])
        ClipboardService.shared.injectPreview([("https://github.com/techInnovator1999/Blinko/pull/42", "Safari"),
                                               ("Blinko v0.4 release notes draft", "Notes"),
                                               ("git rebase -i origin/main", "Terminal")])
        let model = CommandBarModel.shared
        let queries: [(String, String)] = [
            ("40-command-empty", ""), ("41-command-calc", "(12 + 4) * 3^2 / 5"), ("41b-command-calc-error", "1/0"),
            ("42-command-units", "10 km to mi"), ("43-command-currency", "100 usd to eur"),
            ("44-command-apps", "sa"), ("45-command-timer", "t 25m"), ("46-command-shortcuts", "short"),
            ("47-command-clipboard", "blinko"), ("48-command-web", "how to bake sourdough"),
        ]
        for (name, query) in queries {
            model.injectPreview(query: query)
            shot(name, 340) { vm in vm.toggleCommandBar() }
        }
    }

    private static func sampleArtwork() -> NSImage {
        let size = NSSize(width: 256, height: 256)
        return NSImage(size: size, flipped: false) { rect in
            let g = NSGradient(colors: [NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                        NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1)])
            g?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 80, dy: 80)).fill()
            return true
        }
    }
}
