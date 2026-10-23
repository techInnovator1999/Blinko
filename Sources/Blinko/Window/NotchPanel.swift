import SwiftUI
import AppKit

/// Borderless, non-activating panel that floats above the menu bar.
/// It never steals focus from the app you're working in.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the island draws its own, shaped shadow
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit normally pushes windows below the menu bar; the island must sit on top of it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view that accepts the first click, so buttons work even when the panel isn't key.
/// Its tracking area is only a *wake-up trigger* for precise hover tracking; hover truth
/// itself is computed geometrically (tracking areas misfire when the window resizes).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onPointerEntered: (() -> Void)?
    private var sensor: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let sensor { removeTrackingArea(sensor) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        sensor = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointerEntered?()
    }
}
