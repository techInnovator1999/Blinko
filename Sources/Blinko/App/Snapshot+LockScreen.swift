import AppKit
import SwiftUI

/// `--snapshot <dir>` (or `--snapshot <dir> --lockscreen-only`): the island in lock-screen
/// mode, the privacy-redacted variants and the widget panel.
extension Snapshot {
    static func renderLockScreen(to dir: URL) {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        let lock = LockScreenSettings.shared
        let savedDetails = lock.calendarDetails
        let savedAgents = lock.showAgents
        let np = NowPlayingService.shared
        let art = lockSampleArtwork()
        func play(_ playing: Bool) {
            np.injectPreview(title: "Midnight City", artist: "M83", duration: 243, elapsed: 97, playing: playing, artwork: art)
        }
        let wallpaper = LinearGradient(colors: [Color(red: 0.13, green: 0.17, blue: 0.36), Color(red: 0.55, green: 0.32, blue: 0.48)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)

        func write(_ view: some View, _ size: CGSize, _ name: String, scale: CGFloat = 2) {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = scale
            guard let cg = renderer.cgImage else { return }
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("\(name).png"))
        }

        func island(_ name: String, lockScreen: Bool = true, setup: (NotchViewModel) -> Void = { _ in }) {
            let vm = NotchViewModel(geometry: geometry)
            vm.isPreview = true
            vm.lockScreenMode = lockScreen
            setup(vm)
            let canvas = CGSize(width: 640, height: max(120, vm.canvasSize.height + 30))
            write(ZStack(alignment: .top) {
                wallpaper
                NotchRootView(vm: vm).frame(width: canvas.width, height: canvas.height)
            }, canvas, name)
        }

        func widgets(_ name: String) {
            write(ZStack { wallpaper; LockScreenWidgetsView() }, LockScreenWidgetPanel.size, name)
        }

        // Island
        play(true)
        island("ls-01-island-music")
        island("ls-02-island-player-open") { $0.open() }
        play(false)
        BatteryService.shared.injectPreview(level: 76, pluggedIn: true)
        island("ls-03-island-charging")
        island("ls-03b-island-no-track-tap-ignored") { vm in
            np.injectPreview(title: "", artist: "", duration: 0, elapsed: 0, playing: false, artwork: nil)
            vm.open() // must stay closed: nothing to expand
        }
        play(false)
        TimerService.shared.startFocus()
        island("ls-04-island-focus-countdown")
        TimerService.shared.cancel()
        play(true)
        ActivityCenter.shared.show(.volume(level: 0.55, muted: false))
        island("ls-05-island-volume-hud")
        // Privacy: a custom alert is shown unlocked but filtered on the lock screen.
        ActivityCenter.shared.show(.custom(CustomAlert(title: "Deploy finished", body: "api-server · prod",
                                                       symbol: "checkmark.seal.fill", color: "green", duration: 4)))
        island("ls-06a-unlocked-custom-alert", lockScreen: false)
        island("ls-06b-locked-custom-alert-hidden")
        ActivityCenter.shared.dismiss()
        // Privacy: agent status hidden unless allowed.
        AgentSpinner.renderStatic = true
        let now = Date()
        AgentHubService.shared.injectPreview(sessions: [
            AgentSession(id: "claude-code:1", agent: "claude-code", cwd: "/Users/me/Projects/secret-project", title: nil,
                         state: .working, detail: "Bash · swift build", tool: "Bash",
                         startedAt: now - 300, updatedAt: now, stateSince: now - 60),
        ], approvals: [])
        island("ls-07a-unlocked-agent", lockScreen: false)
        lock.showAgents = false
        island("ls-07b-locked-agent-hidden")
        lock.showAgents = true
        island("ls-07c-locked-agent-allowed")
        lock.showAgents = savedAgents
        AgentHubService.shared.injectPreview(sessions: [], approvals: [])

        // Widget panel
        BatteryService.shared.injectPreview(level: 76, pluggedIn: false)
        LockNextEvent.preview = AgendaItem(id: "e1", title: "1:1 with Sam — salary review", start: now + 25 * 60,
                                           end: now + 55 * 60, isAllDay: false, color: .systemPurple,
                                           meetingURL: nil, isReminder: false)
        TimerService.shared.start(20 * 60, label: "Tea")
        lock.calendarDetails = false
        widgets("ls-10-widgets-redacted")
        lock.calendarDetails = true
        widgets("ls-11-widgets-calendar-details")
        lock.calendarDetails = savedDetails
        TimerService.shared.cancelAllCountdowns()
        LockNextEvent.preview = nil
        widgets("ls-12-widgets-music-battery")
        play(false)
        BatteryService.shared.injectPreview(level: 18, pluggedIn: false)
        np.injectPreview(title: "", artist: "", duration: 0, elapsed: 0, playing: false, artwork: nil)
        widgets("ls-13-widgets-battery-only")

        // Whole lock screen, to judge placement (1512 × 982 pt display, 1× scale).
        play(true)
        BatteryService.shared.injectPreview(level: 76, pluggedIn: true)
        let screen = CGSize(width: 1512, height: 982)
        let screenGeometry = NotchGeometry(screenFrame: CGRect(origin: .zero, size: screen),
                                           notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        let vm = NotchViewModel(geometry: screenGeometry)
        vm.isPreview = true
        vm.lockScreenMode = true
        let panelTop = screen.height / 2 + 40 // y measured from the top, mirrors LockScreenWidgetPanel.place()
        write(ZStack(alignment: .top) {
            wallpaper
            VStack(spacing: 0) {
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                Text(now.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 96, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 70)
            NotchRootView(vm: vm).frame(width: vm.canvasSize.width, height: vm.canvasSize.height)
            LockScreenWidgetsView()
                .frame(width: LockScreenWidgetPanel.size.width, height: LockScreenWidgetPanel.size.height)
                .padding(.top, panelTop)
            Circle().fill(.white.opacity(0.25)).frame(width: 64, height: 64)
                .overlay(Image(systemName: "person.fill").font(.system(size: 28)).foregroundStyle(.white))
                .padding(.top, screen.height - 170)
        }, screen, "ls-20-lockscreen-mock", scale: 1)
    }

    private static func lockSampleArtwork() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1)])?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 80, dy: 80)).fill()
            return true
        }
    }
}
