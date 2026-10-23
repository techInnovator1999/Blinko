import AppKit
import SwiftUI

/// v0.5 launch polish for design QA: every tour page, the crash prompt and each Settings pane,
/// plus `--locale xx` to render everything in one language.
///
/// `Blinko --snapshot <dir> --locale de` re-runs itself with `-AppleLanguages (de)` (so
/// `String(localized:)` and AppKit pick the language, without touching saved preferences) and
/// sets the SwiftUI locale and layout direction (right-to-left for Urdu) on every rendered view.
/// Run it from the built app (`build/Blinko.app/Contents/MacOS/Blinko`): the translations are
/// compiled into the bundle's `.lproj` folders by build.sh.
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

    /// Renders through an offscreen window so buttons, toggles and forms draw as real controls.
    static func hosted<V: View>(_ view: V, size: CGSize, name: String, to dir: URL) {
        let host = NSHostingView(rootView: localized(view)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: size)
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
}
