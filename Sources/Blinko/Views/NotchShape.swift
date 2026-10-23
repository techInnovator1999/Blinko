import SwiftUI

/// The island silhouette: concave "ears" at the top that melt into the bezel like the
/// hardware notch, and soft continuous corners at the bottom. Both radii animate.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.height - t) / 1.2, rect.width / 4)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear (concave).
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        // Bottom-left (convex, cubic for a squircle-like continuous curve).
        p.addCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + t, y: rect.maxY - b * 0.45),
                   control2: CGPoint(x: rect.minX + t + b * 0.45, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                   control1: CGPoint(x: rect.maxX - t - b * 0.45, y: rect.maxY),
                   control2: CGPoint(x: rect.maxX - t, y: rect.maxY - b * 0.45))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // Right ear.
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Transitions

private struct IslandRevealModifier: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale, anchor: .top)
    }
}

extension AnyTransition {
    /// Content blooms out of the notch: blur → sharp, slight scale from the top edge.
    static var islandReveal: AnyTransition {
        // Reduced motion: a plain cross-fade, no blur or scale.
        if Motion.reduced {
            return .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.16)),
                               removal: .opacity.animation(.easeIn(duration: 0.1)))
        }
        return .asymmetric(
            insertion: .modifier(active: IslandRevealModifier(blur: 5, opacity: 0, scale: 0.95),
                                 identity: IslandRevealModifier(blur: 0, opacity: 1, scale: 1))
                .animation(.spring(response: 0.34, dampingFraction: 0.92).delay(0.06)),
            removal: .modifier(active: IslandRevealModifier(blur: 3, opacity: 0, scale: 0.97),
                               identity: IslandRevealModifier(blur: 0, opacity: 1, scale: 1))
                .animation(.easeIn(duration: 0.1))
        )
    }

    static var wingReveal: AnyTransition {
        if Motion.reduced { return .opacity }
        return .modifier(active: IslandRevealModifier(blur: 4, opacity: 0, scale: 0.6),
                  identity: IslandRevealModifier(blur: 0, opacity: 1, scale: 1))
    }
}
