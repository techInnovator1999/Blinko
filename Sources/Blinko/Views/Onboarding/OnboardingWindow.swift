import AppKit
import SwiftUI

/// First-run guided tour: six short steps (about a minute), skippable at any point with
/// "Skip" or esc. Shown once at first launch and again from Settings → About → Show Tour.
/// The window and its views (and therefore every illustration task) exist only while it is open.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = String(localized: "Welcome to Blinko")
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(white: 0.06, alpha: 1)
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView { [weak self] openIsland in
                self?.finish(openIsland: openIsland)
            })
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish(openIsland: Bool) {
        window?.close() // windowWillClose marks the tour as seen
        if openIsland {
            // Show the real island once, so the tour ends on the thing itself.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { AppRouter.shared.open(tab: .home) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        Preferences.shared.hasCompletedOnboarding = true
        // Drop the hosting view so illustrations and permission polling stop with the window.
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentView = nil
            self?.window = nil
        }
    }
}

enum TourStep: Int, CaseIterable, Identifiable {
    case meet, open, commandBar, shelf, permissions, finale
    var id: Int { rawValue }
}

struct OnboardingView: View {
    /// Called with `true` when the tour ends on "Start Using Blinko".
    let finish: (Bool) -> Void
    var initialStep: TourStep = .meet

    @State private var step: TourStep?
    @State private var forward = true
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let current = step ?? initialStep
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if current != .finale {
                    Button("Skip Tour") { finish(false) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            ZStack {
                page(current)
                    .id(current)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer(current)
        }
        .frame(width: 720, height: 600)
        .background(TourBackground())
        .environment(\.colorScheme, .dark)
        .tint(Theme.shared.accent)
    }

    private var pageTransition: AnyTransition {
        guard !Motion.reduced else { return .opacity }
        // Pages slide in the reading direction (mirrored for right-to-left languages).
        let sign: CGFloat = (forward ? 1 : -1) * (direction == .rightToLeft ? -1 : 1)
        return .asymmetric(insertion: .offset(x: 36 * sign).combined(with: .opacity),
                           removal: .offset(x: -36 * sign).combined(with: .opacity))
    }

    private func go(to target: TourStep) {
        forward = target.rawValue > (step ?? initialStep).rawValue
        withAnimation(Motion.open) { step = target }
    }

    @ViewBuilder
    private func page(_ s: TourStep) -> some View {
        switch s {
        case .meet: MeetStep()
        case .open: OpenStep()
        case .commandBar: CommandBarStep()
        case .shelf: ShelfStep()
        case .permissions: PermissionsStep()
        case .finale: FinaleStep()
        }
    }

    private func footer(_ current: TourStep) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(TourStep.allCases) { s in
                    Button { go(to: s) } label: {
                        Capsule()
                            .fill(s == current ? Theme.shared.accent : Color.white.opacity(0.22))
                            .frame(width: s == current ? 18 : 7, height: 7)
                            .contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Step \(s.rawValue + 1) of \(TourStep.allCases.count)"))
                }
            }
            .animation(Motion.micro, value: current)
            Spacer()
            if current != .meet {
                Button("Back") { go(to: TourStep(rawValue: current.rawValue - 1)!) }
                    .controlSize(.large)
            }
            if current == .finale {
                Button("Start Using Blinko") { finish(true) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { go(to: TourStep(rawValue: current.rawValue + 1)!) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(Rectangle().fill(Color.white.opacity(0.03)).overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
        })
    }
}

/// Near-black backdrop with a soft accent bloom where the notch would be.
private struct TourBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(white: 0.06)
            RadialGradient(colors: [Theme.shared.accent.opacity(0.20), .clear],
                           center: .top, startRadius: 0, endRadius: 420)
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page scaffold

/// Illustration on top, then title and a short explanation, then optional extras.
struct TourPage<Stage: View, Extra: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var stageHeight: CGFloat = 236
    @ViewBuilder var stage: Stage
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            stage
                .frame(height: stageHeight)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(message)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 540)
            }
            .padding(.top, 22)
            .padding(.horizontal, 40)
            extra
                .padding(.top, 18)
                .padding(.horizontal, 40)
            Spacer(minLength: 0)
            Spacer(minLength: 0) // sits a little above centre

        }
    }
}

/// A key cap, for shortcuts shown in the tour.
struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(verbatim: key)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .frame(minWidth: 24, minHeight: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            }
        }
        .environment(\.layoutDirection, .leftToRight) // shortcuts read ⌃⌥Space in every language
    }

    /// The configured island shortcut (⌃⌥Space by default) as key caps.
    @MainActor static var island: [String] {
        let p = Preferences.shared
        return split(HotkeyFormat.symbols(for: p.hotkeyModifiers), p.hotkeyKeyName)
    }

    /// The configured command bar shortcut (⌥Space by default).
    @MainActor static var commandBar: [String] {
        let p = Preferences.shared
        return split(HotkeyFormat.symbols(for: p.commandHotkeyModifiers), p.commandHotkeyKeyName)
    }

    private static func split(_ modifiers: String, _ key: String) -> [String] {
        modifiers.map(String.init) + [key == "Space" ? String(localized: "Space", comment: "The space bar key") : key]
    }
}
