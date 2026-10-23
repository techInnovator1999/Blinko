import AppKit
import SwiftUI

/// Owns one island on one display. The window is resized to the island's footprint so
/// the rest of the menu bar stays clickable: it grows instantly (content is transparent)
/// and shrinks only after the closing spring has settled.
@MainActor
final class NotchWindowController {
    let screen: NSScreen
    let viewModel: NotchViewModel
    let panel = NotchPanel()

    private var shrinkWork: DispatchWorkItem?
    var onPointerEntered: (() -> Void)?
    private var currentSize: CGSize = .zero
    private(set) var isHiddenForFullscreen = false

    init(screen: NSScreen) {
        self.screen = screen
        self.viewModel = NotchViewModel(geometry: .make(for: screen))

        let hosting = NotchHostingView(rootView: NotchRootView(vm: viewModel))
        hosting.sizingOptions = [] // never let SwiftUI drive window size (avoids layout feedback loops)
        hosting.onPointerEntered = { [weak self] in self?.onPointerEntered?() }
        panel.contentView = hosting

        applyCanvas(viewModel.canvasSize, immediately: true)
        panel.orderFrontRegardless()
        trackCanvasSize()
    }

    func tearDown() {
        shrinkWork?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    func refreshGeometry() {
        let g = NotchGeometry.make(for: screen)
        if g != viewModel.geometry { viewModel.geometry = g }
        applyCanvas(viewModel.canvasSize, immediately: true)
    }

    func setHiddenForFullscreen(_ hidden: Bool) {
        guard hidden != isHiddenForFullscreen else { return }
        isHiddenForFullscreen = hidden
        if hidden { viewModel.close() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = hidden ? 0 : 1
        }
        panel.ignoresMouseEvents = hidden
    }

    // MARK: Sizing

    private func trackCanvasSize() {
        withObservationTracking {
            _ = viewModel.canvasSize
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyCanvas(self.viewModel.canvasSize, immediately: false)
                self.trackCanvasSize()
            }
        }
    }

    private func applyCanvas(_ size: CGSize, immediately: Bool) {
        let growing = size.width > currentSize.width || size.height > currentSize.height
        shrinkWork?.cancel()

        if immediately || growing {
            // Grow to the union so a simultaneous width-shrink/height-grow never clips.
            let target = immediately ? size : CGSize(width: max(size.width, currentSize.width),
                                                     height: max(size.height, currentSize.height))
            setFrame(target)
            if !immediately, target != size { scheduleShrink(to: size) }
        } else {
            scheduleShrink(to: size)
        }
    }

    private func scheduleShrink(to size: CGSize) {
        let work = DispatchWorkItem { [weak self] in self?.setFrame(size) }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func setFrame(_ size: CGSize) {
        currentSize = size
        let s = screen.frame
        let frame = CGRect(x: (s.midX - size.width / 2).rounded(),
                           y: s.maxY - size.height,
                           width: size.width.rounded(),
                           height: size.height)
        panel.setFrame(frame, display: true, animate: false)
    }
}
