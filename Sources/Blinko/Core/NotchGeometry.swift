import AppKit

/// Physical description of the notch (or a virtual one on displays without a notch).
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasNotch: Bool

    static func make(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(screenFrame: frame,
                                 notchSize: CGSize(width: width.rounded(), height: topInset),
                                 hasNotch: true)
        }
        // Virtual island sized to the menu bar so it reads as part of the chrome.
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height = menuBar > 0 ? min(max(menuBar, 24), 32) : 24
        return NotchGeometry(screenFrame: frame,
                             notchSize: CGSize(width: 180, height: height),
                             hasNotch: false)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }
}
