import AppKit
import SwiftUI

/// v0.5 launch polish for design QA: every tour page, the crash prompt and each Settings pane,
/// plus `--locale xx` to render everything in one language.
///
/// `Blinko --snapshot <dir> --locale de` re-runs itself with `-AppleLanguages (de)` (so
/// `String(localized:)` and AppKit pick the language, without touching saved preferences) and
/// sets the SwiftUI locale and layout direction (right-to-left for Urdu) on every rendered view.
/// The translations must sit next to the binary: compile them into the build folder first
/// (`xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory .build/debug`).
/// Don't run the snapshot from build/Blinko.app: it would share (and briefly change) the
/// installed app's preferences.
@MainActor
extension Snapshot {
    /// The language requested with `--locale`, if any.
    static var localeOverride: Locale? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--locale"), i + 1 < args.count else { return nil }
        return Locale(identifier: args[i + 1])
    }

    static var layoutDirection: LayoutDirection {
        guard let locale = localeOverride else { return .leftToRight }
        return Locale.Language(identifier: locale.identifier).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    /// Re-executes with `-AppleLanguages` when `--locale` is given without it. Returns true when
    /// the child did the work.
    static func relaunchForLocaleIfNeeded() -> Bool {
        let args = CommandLine.arguments
        guard let locale = localeOverride, !args.contains("-AppleLanguages") else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst()) + ["-AppleLanguages", "(\(locale.identifier))"]
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return true
    }

    /// Applies the requested locale to a view about to be rendered.
    static func localized<V: View>(_ view: V) -> some View {
        view
            .environment(\.locale, localeOverride ?? .current)
            .environment(\.layoutDirection, layoutDirection)
    }

    static func renderLaunch(to dir: URL) {
        for step in TourStep.allCases {
            hosted(OnboardingView(finish: { _ in }, initialStep: step), size: CGSize(width: 720, height: 600),
                   name: "50-tour-\(step.rawValue + 1)", to: dir)
        }
        hosted(CrashPromptView(review: {}, dismiss: {}), size: CGSize(width: 380, height: 150), name: "51-crash-prompt", to: dir)
        let selection = SettingsSelection()
        for pane in SettingsPane.allCases where pane != .welcome {
            selection.pane = pane
            hosted(SettingsView(selection: selection), size: CGSize(width: 740, height: 580),
                   name: "52-settings-\(pane.rawValue)", to: dir)
        }
    }

    /// Island states for the landing page (`--site-only`): real views rendered through AppKit
    /// (ImageRenderer can't draw the AppKit-backed pieces) on a transparent canvas.
    static func renderSite(to dir: URL) {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        let art = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.36, blue: 0.52, alpha: 1),
                                NSColor(red: 0.36, green: 0.22, blue: 0.82, alpha: 1)])?.draw(in: rect, angle: -45)
            return true
        }
        NowPlayingService.shared.injectPreview(title: "Midnight City", artist: "M83", duration: 243, elapsed: 97,
                                               playing: true, artwork: art)
        BatteryService.shared.injectPreview(level: 84, pluggedIn: false)
        // Placeholder lyric: never ship real (copyrighted) lyrics fetched from LRCLIB.
        LyricsService.shared.injectPreview(key: LyricsService.key(title: "Midnight City", artist: "M83"),
                                           lrc: "[01:20.00] —\n[01:35.00] Neon lights over a sleeping town tonight\n[01:44.00] —")
        func island(_ name: String, compact: CompactContent? = nil, tab: NotchTab? = nil, command: String? = nil) {
            let vm = NotchViewModel(geometry: geometry)
            vm.isPreview = true
            vm.compactOverride = compact
            if let tab { vm.open(tab: tab) }
            if let command {
                CommandBarModel.shared.injectPreview(query: command)
                vm.toggleCommandBar()
            }
            let size = CGSize(width: vm.canvasSize.width, height: vm.shapeSize.height + 4)
            hosted(NotchRootView(vm: vm), size: size, name: name, to: dir, transparent: true)
        }
        island("compact-music", compact: .music)
        island("compact-hud", compact: .activity(.volume(level: 0.62, muted: false)))
        island("compact-focus", compact: .activity(.focusMode(on: true, name: "Do Not Disturb", symbol: "moon.fill")))
        island("compact-airpods", compact: .activity(.bluetooth(name: "AirPods Pro", kind: .headphones, connected: true,
                                                                battery: DeviceBattery(left: 82, right: 76, caseLevel: 54))))
        island("open-home", tab: .home)
        island("open-shelf", tab: .shelf)
        island("open-timers", tab: .timer)
        AppIndex.shared.injectPreview()
        island("command", command: "10 km to mi")
        let meetingMode = Preferences.shared.meetingMode
        Preferences.shared.meetingMode = true
        MeetingService.shared.injectPreview(app: "zoom", started: Date().addingTimeInterval(-754))
        PrivacyService.shared.injectPreview(camera: false, mic: true)
        island("compact-meeting")
        island("open-meeting", tab: .home)
        MeetingService.shared.injectPreview(app: nil)
        PrivacyService.shared.injectPreview(camera: false, mic: false)
        Preferences.shared.meetingMode = meetingMode
        let now = Date()
        let session = AgentSession(id: "claude-code:1", agent: "claude-code", cwd: "/Users/me/Projects/blinko", title: nil,
                                   state: .waiting, detail: "Bash · swift build -c release", tool: "Bash",
                                   startedAt: now - 900, updatedAt: now, stateSince: now - 20)
        let approval = AgentApproval(id: "r1", sessionID: session.id, connection: 0, agent: "claude-code", project: "blinko",
                                     tool: "Bash", summary: "swift build -c release --arch arm64 --arch x86_64",
                                     detail: "Build the universal binary", receivedAt: now, deadline: now + 72)
        AgentHubService.shared.injectPreview(sessions: [session], approvals: [approval])
        island("compact-agent")
        island("open-agents", tab: .agents)
        AgentHubService.shared.injectPreview(sessions: [], approvals: [])
        let saved = ThemeLibrary.current
        for theme in ThemeFile.builtIns {
            ThemeLibrary.apply(theme)
            island("theme-\(theme.name.lowercased())", tab: .home)
        }
        ThemeLibrary.apply(saved)
    }

    /// Renders through an offscreen window so buttons, toggles and forms draw as real controls.
    static func hosted<V: View>(_ view: V, size: CGSize, name: String, to dir: URL, transparent: Bool = false) {
        let host = NSHostingView(rootView: localized(view)
            .background(transparent ? Color.clear : Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        if transparent {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
