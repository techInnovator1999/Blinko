import SwiftUI

/// Every animation in the app comes from here so the motion language stays coherent.
/// All springs are interruptible: retargeting mid-flight keeps velocity, no snapping.
enum Motion {
    static let open = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let close = Animation.spring(response: 0.32, dampingFraction: 1)
    static let compact = Animation.spring(response: 0.4, dampingFraction: 0.76)
    static let peek = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let micro = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let content = Animation.easeOut(duration: 0.22)
}

enum Metrics {
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 14
    static let openTopRadius: CGFloat = 19
    static let openBottomRadius: CGFloat = 26
    static let openSize = CGSize(width: 660, height: 196)
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
