import AppKit
import SwiftUI

/// The Blinko mark: the island as an eyelid, mid-blink over an iris.
enum BrandMark {
    /// Monochrome template version for the menu bar (adapts to light/dark automatically).
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            // Iris (centre just under the lid) with a punched-out pupil.
            let iris = NSBezierPath(ovalIn: NSRect(x: 3.6, y: 5.2, width: 10.8, height: 10.8))
            iris.appendOval(in: NSRect(x: 7.1, y: 8.9, width: 3.8, height: 3.8))
            iris.windingRule = .evenOdd
            iris.fill()
            // Clear a 1.2pt gap around the lid so the two shapes read separately.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: NSRect(x: 1.3, y: -6, width: 15.4, height: 15.6), xRadius: 5, yRadius: 5).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            // Lid: the island hanging from the top edge.
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: -6, width: 13, height: 14.4), xRadius: 4, yRadius: 4).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The app icon, for Settings / onboarding.
struct AppIconView: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
