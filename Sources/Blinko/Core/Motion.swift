import AppKit
import SwiftUI

/// Every animation in the app comes from here so the motion language stays coherent.
/// All springs are interruptible: retargeting mid-flight keeps velocity, no snapping.
/// With Reduce Motion (system setting or the app's override) springs become short fades.
enum Motion {
    static var open: Animation { reduced ? fade : .spring(response: 0.4, dampingFraction: 0.8) }
    static var close: Animation { reduced ? fade : .spring(response: 0.32, dampingFraction: 1) }
    static var compact: Animation { reduced ? fade : .spring(response: 0.4, dampingFraction: 0.76) }
    static var peek: Animation { reduced ? fade : .spring(response: 0.3, dampingFraction: 0.7) }
    static var micro: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.86) }
    static let content = Animation.easeOut(duration: 0.22)

    private static let fade = Animation.easeInOut(duration: 0.18)

    /// Cached so every animation lookup is a plain load. Written on the main thread only.
    nonisolated(unsafe) private(set) static var reduced = false

    /// Reads the system setting once, then follows its change notification (no polling).
    @MainActor
    static func startObservingReducedMotion() {
        update()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { _ in MainActor.assumeIsolated { update() } }
        observePreference()
    }

    @MainActor
    private static func observePreference() {
        withObservationTracking { _ = Preferences.shared.reduceMotion } onChange: {
            DispatchQueue.main.async { update(); observePreference() }
        }
    }

    @MainActor
    private static func update() {
        reduced = Preferences.shared.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

enum Metrics {
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 14
    static let openTopRadius: CGFloat = 19
    static let openBottomRadius: CGFloat = 26
    static let openSize = CGSize(width: 700, height: 210)
    /// Transparent room around the open island so its shadow is not clipped by the window.
    static let shadowPadding: CGFloat = 28
    static let peekGrowth = CGSize(width: 18, height: 5)
}

extension Color {
    static let notchBackground = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.6)
    static let tertiaryText = Color.white.opacity(0.38)
    static let hairline = Color.white.opacity(0.08)
    static let fillSubtle = Color.white.opacity(0.07)
    static let fillHover = Color.white.opacity(0.12)
}
