import AppKit
import SwiftUI

/// Home layouts for design QA: every built-in layout × size preset, dense custom layouts,
/// the meeting takeover, an empty layout, edit mode and the Home Layout pane.
/// Rendered through an offscreen window so AppKit-backed views (Notes' text editor) draw.
/// `Blinko --snapshot <dir>` renders it last; `--home-only` renders just this.
@MainActor
extension Snapshot {
    static func renderHome(to dir: URL) {
        let prefs = Preferences.shared
        let saved = (layouts: prefs.homeLayouts, id: prefs.homeLayoutID, width: prefs.openWidth,
                     weather: prefs.weatherEnabled, clocks: prefs.worldClocks, meeting: prefs.meetingMode,
                     style: prefs.islandStyle)
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        prefs.islandStyle = .classic
        injectHomeData()

        // Stats widgets need two samples for CPU; let the sampler run briefly.
        let stats = SystemStatsService.shared
        stats.beginObserving()
        RunLoop.current.run(until: Date().addingTimeInterval(2.2))

        func shot(_ name: String, editing: Bool = false) {
            let vm = NotchViewModel(geometry: geometry)
            vm.isPreview = true
            vm.open(tab: .home)
            let canvas = CGSize(width: max(760, vm.canvasSize.width + 40), height: max(280, vm.canvasSize.height + 50))
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.75, green: 0.55, blue: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                NotchRootView(vm: vm).frame(width: canvas.width, height: canvas.height)
                    .environment(\.homeLayoutEditing, editing)
            }
            .frame(width: canvas.width, height: canvas.height)
            hostedShot(view, size: canvas, name, to: dir)
        }

        // Built-ins × size presets.
        for layout in HomeLayout.builtIns {
            prefs.homeLayoutID = layout.id
            for size in SizePreset.choices {
                prefs.openWidth = size.width!
                shot("50-home-\(layout.id.replacingOccurrences(of: "builtin.", with: ""))-\(size.rawValue)")
            }
        }
        prefs.openWidth = 700

        // Custom layouts: dense, mixed and large widgets.
        let customs: [(String, [HomeSlot])] = [
            ("dense-small", [HomeSlot(.clock, .small), HomeSlot(.weather, .small), HomeSlot(.stats, .small),
                             HomeSlot(.battery, .small), HomeSlot(.agents, .small)]),
            ("dense-mixed", [HomeSlot(.nowPlaying, .medium), HomeSlot(.timers, .medium),
                             HomeSlot(.clipboard, .small), HomeSlot(.shelf, .small)]),
            ("medium-cards", [HomeSlot(.clock, .medium), HomeSlot(.weather, .medium), HomeSlot(.stats, .medium)]),
            ("large-pair", [HomeSlot(.agents, .large), HomeSlot(.timers, .large)]),
            ("notes-shelf", [HomeSlot(.notes, .large), HomeSlot(.shelf, .large)]),
            ("agenda-clipboard", [HomeSlot(.agenda, .large), HomeSlot(.clipboard, .medium), HomeSlot(.mirror, .small)]),
            ("two-small", [HomeSlot(.battery, .small), HomeSlot(.mirror, .small)]),
        ]
        for (name, slots) in customs {
            prefs.homeLayouts = [HomeLayout(id: "snap-\(name)", name: name, slots: slots)]
            prefs.homeLayoutID = "snap-\(name)"
            shot("52-home-\(name)")
        }
        // The densest layout at the narrowest and widest presets.
        prefs.homeLayouts = [HomeLayout(id: "snap-dense", name: "dense", slots: customs[1].1)]
        prefs.homeLayoutID = "snap-dense"
        for width in [600.0, 640, 780, 840] {
            prefs.openWidth = width
            shot("52-home-dense-mixed-\(Int(width))")
        }
        prefs.openWidth = 700

        // Running timers and a Pomodoro in the timer widgets.
        TimerService.shared.start(1500, label: Format.duration(1500))
        prefs.homeLayoutID = HomeLayout.work.id
        shot("53-home-work-timer-running")
        prefs.homeLayouts = [HomeLayout(id: "snap-timers", name: "timers",
                                        slots: [HomeSlot(.timers, .small), HomeSlot(.timers, .medium), HomeSlot(.timers, .large)])]
        prefs.homeLayoutID = "snap-timers"
        shot("53b-home-timers-sizes")
        TimerService.shared.cancelAllCountdowns()

        // Features off: weather and Agent Hub hints.
        prefs.weatherEnabled = false
        let hub = prefs.agentHubEnabled
        prefs.agentHubEnabled = false
        prefs.homeLayouts = [HomeLayout(id: "snap-off", name: "off",
                                        slots: [HomeSlot(.weather, .medium), HomeSlot(.agents, .medium), HomeSlot(.clipboard, .medium)])]
        prefs.homeLayoutID = "snap-off"
        ClipboardService.shared.clear()
        shot("54-home-features-off")
        prefs.agentHubEnabled = hub
        prefs.weatherEnabled = true
        ClipboardService.shared.injectPreview([("git rebase -i origin/main", "Terminal"),
                                               ("Blinko v0.5 release notes draft", "Notes"),
                                               ("https://github.com/techInnovator1999/Blinko", "Safari")])

        // Meeting takeover: the large player slot and the medium Now Playing card.
        prefs.meetingMode = true
        MeetingService.shared.injectPreview(app: "facetime", started: Date().addingTimeInterval(-754))
        prefs.homeLayoutID = HomeLayout.defaultID
        shot("55-home-meeting-default")
        prefs.homeLayoutID = HomeLayout.chill.id
        shot("55b-home-meeting-chill")
        prefs.homeLayouts = [HomeLayout(id: "snap-dense", name: "dense", slots: customs[1].1)]
        prefs.homeLayoutID = "snap-dense"
        MeetingService.shared.injectPreview(app: "teams", started: Date().addingTimeInterval(-1_312), micMuted: true)
        shot("55c-home-meeting-medium")
        MeetingService.shared.injectPreview(app: nil)

        // Empty layout, and edit mode with room left.
        prefs.homeLayouts = [HomeLayout(id: "snap-empty", name: "empty", slots: [])]
        prefs.homeLayoutID = "snap-empty"
        shot("56-home-empty")
        shot("56b-home-empty-editing", editing: true)
        prefs.homeLayouts = [HomeLayout(id: "snap-edit", name: "My Layout",
                                        slots: [HomeSlot(.nowPlaying, .large), HomeSlot(.clock, .small)])]
        prefs.homeLayoutID = "snap-edit"
        shot("56c-home-editing", editing: true)
        prefs.homeLayoutID = HomeLayout.work.id
        shot("56d-home-editing-full", editing: true)

        // The Settings pane (a custom layout so the name field and Delete show).
        prefs.homeLayouts = [HomeLayout(id: "snap-pane", name: "Studio", slots: customs[1].1)]
        prefs.homeLayoutID = "snap-pane"
        let pane = { HomeLayoutPane().frame(width: 550, height: 1000).background(Color(nsColor: .windowBackgroundColor)) }
        hostedShot(pane(), size: CGSize(width: 550, height: 1000), "57-home-layout-pane", to: dir)
        prefs.homeLayoutID = HomeLayout.defaultID
        hostedShot(pane(), size: CGSize(width: 550, height: 1000), "57b-home-layout-pane-default", to: dir)

        // JSON round trip of a custom layout (unknown widgets are skipped, capacity enforced).
        let sample = HomeLayout(id: "x", name: "Round trip", slots: customs[0].1)
        if let data = HomeLayout.encodeList([sample]) {
            let back = HomeLayout.decodeList(data)
            print("home layout JSON round trip:", back.first?.slots == sample.slots ? "ok" : "MISMATCH")
            var json = String(decoding: data, as: UTF8.self)
            json = json.replacingOccurrences(of: "\"clock\"", with: "\"hologram\"")
            print("unknown widget skipped:", HomeLayout.decodeList(Data(json.utf8)).first?.slots.count == sample.slots.count - 1 ? "ok" : "MISMATCH")
        }

        stats.endObserving()
        prefs.homeLayouts = saved.layouts
        prefs.homeLayoutID = saved.id
        prefs.openWidth = saved.width
        prefs.weatherEnabled = saved.weather
        prefs.worldClocks = saved.clocks
        prefs.meetingMode = saved.meeting
        prefs.islandStyle = saved.style
    }

    /// Sample data for every widget.
    private static func injectHomeData() {
        let np = NowPlayingService.shared
        np.injectPreview(title: "Midnight City", artist: "M83", duration: 243, elapsed: 97, playing: true,
                         artwork: NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
                             NSGradient(colors: [NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                                 NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1)])?.draw(in: rect, angle: -45)
                             NSColor.white.withAlphaComponent(0.85).setFill()
                             NSBezierPath(ovalIn: rect.insetBy(dx: 80, dy: 80)).fill()
                             return true
                         })
        let hour = Calendar.current.dateInterval(of: .hour, for: .now)!.start
        let codes = [2, 3, 61, 3, 1]
        WeatherService.shared.injectPreview(.init(
            temperature: 18.4, code: 2, isDay: true, high: 21, low: 12,
            hours: (1...5).map { i in .init(date: hour.addingTimeInterval(Double(i) * 3600), temperature: 18 + Double(i % 3),
                                             code: codes[i - 1], isDay: true) },
            place: "Brussels", fetchedAt: .now))
        Preferences.shared.weatherEnabled = true
        Preferences.shared.worldClocks = ["America/New_York", "Asia/Tokyo"]

        let colors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple]
        let titles = ["Design review", "Lunch with Sam", "Ship v0.5 build", "1:1 with Alex"]
        CalendarService.shared.injectPreview((0..<4).map { i in
            let start = hour.addingTimeInterval(Double(i + 1) * 3600)
            return AgendaItem(id: "\(i)", title: titles[i], start: start, end: start.addingTimeInterval(1800),
                              isAllDay: false, color: colors[i],
                              meetingURL: i == 0 ? URL(string: "https://meet.google.com/abc") : nil, isReminder: i == 2)
        })

        NotesService.shared.injectPreview(
            text: "Call Sam about the launch deck\n— ship the v0.5 build to beta testers\n— renew domain before Friday",
            snippets: ["hello@blinko.app"])
        ClipboardService.shared.injectPreview([("git rebase -i origin/main", "Terminal"),
                                               ("Blinko v0.5 release notes draft", "Notes"),
                                               ("https://github.com/techInnovator1999/Blinko", "Safari")])
        let root = Bundle.main.executableURL!.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        ShelfService.shared.injectPreview(["README.md", "Package.swift", "docs/ROADMAP.md", "Resources/AppIcon.icns"]
            .map { root.appendingPathComponent($0) } + [URL(fileURLWithPath: "/System/Applications/Calculator.app")])
        BatteryService.shared.injectPreview(level: 76, pluggedIn: false)

        AgentSpinner.renderStatic = true
        let now = Date()
        AgentHubService.shared.injectPreview(sessions: [
            AgentSession(id: "claude-code:1", agent: "claude-code", cwd: "/Users/me/Projects/blinko", title: nil,
                         state: .working, detail: "Bash · swift build -c release", tool: "Bash",
                         startedAt: now - 900, updatedAt: now, stateSince: now - 260),
            AgentSession(id: "codex:2", agent: "codex", cwd: "/Users/me/Projects/website", title: nil,
                         state: .working, detail: "Edit · src/pages/index.tsx", tool: "Edit",
                         startedAt: now - 1800, updatedAt: now, stateSince: now - 75),
            AgentSession(id: "claude-code:3", agent: "claude-code", cwd: "/Users/me/Projects/api-server", title: nil,
                         state: .idle, detail: "Finished · all 214 tests pass", tool: nil,
                         startedAt: now - 5400, updatedAt: now - 600, stateSince: now - 600, cost: 0.84),
        ], approvals: [])
        ActivityCenter.shared.dismiss()
        TimerService.shared.cancel()
        TimerService.shared.cancelAllCountdowns()
    }

    /// Renders through an offscreen window so AppKit-backed views draw as real controls.
    static func hostedShot<V: View>(_ view: V, size: CGSize, _ name: String, to dir: URL) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        }
        window.contentView = nil // tear the views down (stops samplers started on appear)
        window.close()
    }
}
