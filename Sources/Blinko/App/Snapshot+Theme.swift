import AppKit
import SwiftUI

/// Theme matrix for design QA: every island style × key states, every size preset × every tab,
/// accents, built-in themes, fonts, corners and the Appearance pane.
/// `Blinko --snapshot <dir>` renders it after the regular states; add `--themes-only` to skip those.
@MainActor
extension Snapshot {
    static func renderThemes(to dir: URL) {
        let prefs = Preferences.shared
        let saved = ThemeLibrary.current
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        let np = NowPlayingService.shared
        if !np.hasTrack {
            np.injectPreview(title: "Midnight City", artist: "M83", duration: 243, elapsed: 97, playing: true,
                             artwork: themeArtwork())
        }
        ActivityCenter.shared.dismiss()

        func shot(_ name: String, compact: CompactContent? = nil, tab: NotchTab? = nil) {
            let vm = NotchViewModel(geometry: geometry)
            vm.isPreview = true
            vm.compactOverride = compact
            if let tab { vm.open(tab: tab) }
            let canvas = CGSize(width: max(760, vm.canvasSize.width + 40), height: max(280, vm.canvasSize.height + 50))
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.75, green: 0.55, blue: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                NotchRootView(vm: vm).frame(width: canvas.width, height: canvas.height)
            }
            .frame(width: canvas.width, height: canvas.height)
            write(view, name, to: dir)
        }

        // Styles × states.
        for style in IslandStyle.allCases {
            prefs.islandStyle = style
            shot("30-\(style.rawValue)-a-closed-music", compact: .music)
            shot("30-\(style.rawValue)-b-hud", compact: .activity(.volume(level: 0.62, muted: false)))
            shot("30-\(style.rawValue)-c-home", tab: .home)
            shot("30-\(style.rawValue)-d-timer", tab: .timer)
        }
        prefs.islandStyle = .classic

        // Size presets × every tab.
        for size in SizePreset.choices {
            prefs.openWidth = size.width!
            for tab in NotchTab.allCases {
                shot("31-\(size.rawValue)-\(tab.rawValue)", tab: tab)
            }
        }
        // Busiest header at the narrowest preset: 7 tabs, Keep Awake, time, battery.
        BatteryService.shared.injectPreview(level: 84, pluggedIn: false)
        KeepAwakeService.shared.injectPreview(until: Date().addingTimeInterval(3600))
        prefs.openWidth = SizePreset.compact.width!
        shot("31-compact-header-full", tab: .stats)
        prefs.openWidth = 600
        shot("31-custom600-header-full", tab: .stats)
        prefs.openWidth = 700

        // Accents.
        for preset in AccentPreset.swatches {
            prefs.accentPreset = preset
            shot("32-accent-\(preset.rawValue)", tab: .timer)
        }
        prefs.accentPreset = .album
        prefs.artworkTint = false
        shot("32-accent-album", tab: .home)
        prefs.artworkTint = true
        prefs.accentPreset = .blinko

        // Fonts and corners.
        prefs.fontStyle = .rounded
        shot("34-rounded-home", tab: .home)
        shot("34-rounded-stats", tab: .stats)
        prefs.fontStyle = .system
        prefs.openCornerRadius = ThemeFile.openRadiusRange.lowerBound
        prefs.closedCornerRadius = ThemeFile.closedRadiusRange.lowerBound
        shot("35-sharp-open", tab: .home)
        shot("35-sharp-closed", compact: .activity(.volume(level: 0.62, muted: false)))
        prefs.openCornerRadius = ThemeFile.openRadiusRange.upperBound
        prefs.closedCornerRadius = ThemeFile.closedRadiusRange.upperBound
        shot("35-round-open", tab: .home)
        shot("35-round-closed", compact: .activity(.volume(level: 0.62, muted: false)))

        // Built-in themes.
        for theme in ThemeFile.builtIns {
            ThemeLibrary.apply(theme)
            shot("33-theme-\(theme.name.lowercased())-home", tab: .home)
            shot("33-theme-\(theme.name.lowercased())-hud", compact: .activity(.volume(level: 0.62, muted: false)))
        }

        // Round trip: export → import gives the same look.
        if let data = try? ThemeLibrary.encode(ThemeFile.builtIns[1]), let back = try? ThemeLibrary.decode(data) {
            print("theme JSON round trip:", back.matches(ThemeFile.builtIns[1]) ? "ok" : "MISMATCH")
            print(String(decoding: data, as: UTF8.self))
        }

        // Appearance preview + the whole pane (AppKit controls need a real view hierarchy).
        ThemeLibrary.apply(ThemeFile.builtIns[3])
        write(ThemePreview(mode: .open, tab: .home, width: 500).padding(10).background(Color(white: 0.93)), "36-preview-open", to: dir)
        write(ThemePreview(mode: .hud, width: 500).padding(10).background(Color(white: 0.93)), "36-preview-hud", to: dir)
        ThemeLibrary.apply(saved)
        writeHosted(AppearancePane().frame(width: 550, height: 1560), "37-appearance-pane", to: dir)

        ThemeLibrary.apply(saved)
    }

    private static func write<V: View>(_ view: V, _ name: String, to dir: URL) {
        let renderer = ImageRenderer(content: localized(view))
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Renders through an offscreen window so Form, Slider and Picker draw as real controls.
    private static func writeHosted<V: View>(_ view: V, _ name: String, to dir: URL) {
        let host = NSHostingView(rootView: localized(view).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: 550, height: 1560)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private static func themeArtwork() -> NSImage {
        NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1)])?.draw(in: rect, angle: -45)
            return true
        }
    }
}
