import SwiftUI

/// The island's fill, shadow and style layers (Glass wash, Glow halo). A leaf view, so a theme
/// change redraws this layer only, never the island's content. The closed island is always
/// plain black: it has to read as the hardware notch.
struct IslandBackdrop: View {
    let shape: NotchShape
    let isOpen: Bool

    var body: some View {
        let theme = Theme.shared
        let style = theme.style
        let shadow = isOpen && Preferences.shared.openShadow
        ZStack {
            if style == .glow {
                // Accent halo beneath the island; the black fill on top hides its core.
                shape
                    .fill(Color.black)
                    .shadow(color: theme.accent.opacity(isOpen ? 0.85 : 0), radius: isOpen ? 20 : 0, y: isOpen ? 8 : 0)
                    .shadow(color: theme.accent.opacity(isOpen ? 0.45 : 0), radius: isOpen ? 6 : 0, y: isOpen ? 2 : 0)
            }
            shape
                .fill(Color.notchBackground)
                .shadow(color: .black.opacity(shadow && style != .glow ? 0.6 : 0),
                        radius: isOpen ? 18 : 0, y: isOpen ? 8 : 0)
            if style == .glass {
                // Frosted wash rising from the bottom edge; the top third stays pure black so
                // the island still melts into the notch and the menu bar.
                shape
                    .fill(LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.36),
                        .init(color: Color.white.opacity(0.06), location: 0.74),
                        .init(color: theme.accent.opacity(0.16), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .opacity(isOpen ? 1 : 0)
            }
        }
    }
}

/// Edge light drawn over the content: a faint hairline (Classic / Minimal), a frosted rim
/// with inner glow (Glass) or an accent-tinted hairline (Glow).
struct IslandRim: View {
    let shape: NotchShape
    let isOpen: Bool

    var body: some View {
        let theme = Theme.shared
        Group {
            switch theme.style {
            case .classic, .minimal:
                shape.stroke(LinearGradient(colors: [.clear, .white.opacity(isOpen ? 0.07 : 0)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1)
            case .glass:
                ZStack {
                    // Inner glow: a wide soft stroke clipped to the inside of the shape.
                    shape.stroke(Color.white.opacity(0.2), lineWidth: 10)
                        .blur(radius: 7)
                        .clipShape(shape)
                    shape.stroke(LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .white.opacity(0.1), location: 0.62),
                        .init(color: .white.opacity(0.26), location: 1),
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.28),
                                             .init(color: .black, location: 0.7)],
                                     startPoint: .top, endPoint: .bottom))
                .opacity(isOpen ? 1 : 0)
            case .glow:
                shape.stroke(LinearGradient(colors: [.clear, theme.accent.opacity(isOpen ? 0.4 : 0)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Lays content out at `size / scale` and scales it to fill `size`: the tab layouts keep their
/// 700 pt design proportions at every size preset instead of reflowing or overflowing.
struct ThemeScaled<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        let scale = Theme.shared.contentScale
        if abs(scale - 1) < 0.001 {
            content.frame(width: size.width, height: size.height, alignment: .top)
        } else {
            content
                .frame(width: size.width / scale, height: size.height / scale, alignment: .top)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}

/// Minimal style: the chrome it is applied to (header, credit) stays hidden until the
/// pointer is over it. Opacity only — the layout and the window never change with hover.
private struct MinimalChrome: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        if Theme.shared.style == .minimal {
            content
                .opacity(hovering ? 1 : 0)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(Motion.content, value: hovering)
        } else {
            content
        }
    }
}

extension View {
    func minimalChrome() -> some View { modifier(MinimalChrome()) }
}

/// Accent outline around a focused text field.
struct FocusRing: View {
    let cornerRadius: CGFloat
    let focused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Theme.shared.accent.opacity(focused ? 0.65 : 0), lineWidth: 1)
            .allowsHitTesting(false)
    }
}
