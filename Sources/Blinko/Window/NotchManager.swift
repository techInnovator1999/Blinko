import AppKit

/// Creates one island per eligible display and routes global input (gestures,
/// hotkey, fullscreen changes) to the right one. Purely event-driven: no polling.
@MainActor
final class NotchManager {
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var scrollMonitor: Any?
    private var mouseMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var scrollAccumulator: CGFloat = 0
    private var horizontalAccumulator: CGFloat = 0
    private var gestureConsumed = false
    private let prefs = Preferences.shared

    func start() {
        rebuild()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFullscreenVisibility() }
            })
        }

        observePreferences()
        installScrollMonitor()
    }

    func toggleOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let target = controllers.values.first { $0.screen.frame.contains(mouse) } ?? controllers.values.first
        target?.viewModel.toggle()
        startHoverTracking()
    }

    /// Command bar on the display under the pointer (where the user is looking).
    func toggleCommandBar() {
        let mouse = NSEvent.mouseLocation
        let target = controllers.values.first { $0.screen.frame.contains(mouse) } ?? controllers.values.first
        guard let target, !target.isHiddenForFullscreen else { return }
        for other in controllers.values where other !== target && other.viewModel.isCommandBarActive {
            other.viewModel.close()
        }
        target.viewModel.toggleCommandBar()
        startHoverTracking()
    }

    func open(tab: NotchTab) {
        let mouse = NSEvent.mouseLocation
        let target = controllers.values.first { $0.screen.frame.contains(mouse) } ?? controllers.values.first
        target?.viewModel.open(tab: tab)
    }

    // MARK: Displays

    private func makeController(for screen: NSScreen) -> NotchWindowController {
        let controller = NotchWindowController(screen: screen)
        controller.onPointerEntered = { [weak self] in self?.startHoverTracking() }
        return controller
    }

    private func eligibleScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch prefs.displayMode {
        case .allDisplays:
            return screens
        case .mainOnly:
            return NSScreen.main.map { [$0] } ?? []
        case .notchedOnly:
            let notched = screens.filter(\.hasNotch)
            if !notched.isEmpty { return notched }
            return (screens.first(where: \.isBuiltIn) ?? NSScreen.main).map { [$0] } ?? []
        }
    }

    private func rebuild() {
        let screens = eligibleScreens()
        let ids = Set(screens.map(\.displayID))

        for (id, controller) in controllers where !ids.contains(id) {
            controller.tearDown()
            controllers[id] = nil
        }
        for screen in screens {
            if let existing = controllers[screen.displayID] {
                if existing.screen.frame != screen.frame {
                    existing.tearDown()
                    controllers[screen.displayID] = makeController(for: screen)
                } else {
                    existing.refreshGeometry()
                }
            } else {
                controllers[screen.displayID] = makeController(for: screen)
            }
        }
        updateFullscreenVisibility()
    }

    private func observePreferences() {
        withObservationTracking {
            _ = prefs.displayMode
            _ = prefs.hideInFullscreen
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.rebuild()
                self?.observePreferences()
            }
        }
    }

    // MARK: Fullscreen

    /// Runs only on space/app switches. Checks whether the frontmost app owns a
    /// window covering a whole display — the signature of a fullscreen space.
    private func updateFullscreenVisibility() {
        guard prefs.hideInFullscreen,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier
        else {
            controllers.values.forEach { $0.setHiddenForFullscreen(false) }
            return
        }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let fullscreenBounds: [CGRect] = info.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary)
            else { return nil }
            return rect
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for controller in controllers.values {
            // Convert AppKit (bottom-left) screen frame into CG (top-left) coordinates.
            let f = controller.screen.frame
            let cgFrame = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            let covered = fullscreenBounds.contains { $0.equalTo(cgFrame) }
            controller.setHiddenForFullscreen(covered)
        }
    }

    // MARK: Hover

    /// Hover is derived from the pointer position and each island's geometry, never from
    /// tracking areas (which macOS rebuilds on every window resize and which caused
    /// open/close flicker). Pointer monitors only run while the pointer is at an island:
    /// the island's tracking area wakes them, and they remove themselves once the pointer
    /// has left and every island is closed — zero wakeups for mouse movement elsewhere.
    private func startHoverTracking() {
        guard mouseMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover(at: NSEvent.mouseLocation) }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.updateHover(at: NSEvent.mouseLocation)
            return event
        }) { mouseMonitors.append(local) }
        lastPointer = nil
        updateHover(at: NSEvent.mouseLocation)
    }

    private func stopHoverTracking() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
    }

    private var lastPointer: (point: CGPoint, time: TimeInterval)?

    private func updateHover(at point: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        var speed: CGFloat = 0
        if let last = lastPointer, now > last.time {
            speed = hypot(point.x - last.point.x, point.y - last.point.y) / CGFloat(now - last.time)
        }
        lastPointer = (point, now)

        for controller in controllers.values where !controller.isHiddenForFullscreen {
            let vm = controller.viewModel
            let inside = vm.contains(screenPoint: point)
            vm.setHovering(inside)
            // Still travelling (> ~280 pt/s): re-arm, so the island opens only once the pointer settles.
            if inside, speed > 280 { vm.pointerPassingThrough() }
        }

        let engaged = controllers.values.contains { $0.viewModel.isHovering || $0.viewModel.isOpen }
        if !engaged { stopHoverTracking() }
    }

    // MARK: Gestures

    /// Two-finger swipe down on the island opens it, swipe up closes it.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.prefs.enableGestures,
                  let controller = self.controllers.values.first(where: { $0.panel === event.window })
            else { return event }

            if event.phase == .began {
                self.scrollAccumulator = 0
                self.horizontalAccumulator = 0
                self.gestureConsumed = false
            }
            guard !self.gestureConsumed else { return event }

            // Normalise for natural scrolling so "down" always means pulling the island down
            // and "left" means swiping content left (→ next track).
            let invert: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            self.scrollAccumulator += event.scrollingDeltaY * invert
            self.horizontalAccumulator += event.scrollingDeltaX * invert

            let vm = controller.viewModel
            let np = NowPlayingService.shared
            let mediaContext = !vm.isOpen ? vm.compact == .music : vm.tab == .home
            let horizontalDominant = abs(self.horizontalAccumulator) > abs(self.scrollAccumulator) * 1.5

            if horizontalDominant, mediaContext, np.hasTrack, abs(self.horizontalAccumulator) > 40 {
                self.horizontalAccumulator < 0 ? np.next() : np.previous()
                if self.prefs.enableHaptics {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
                self.gestureConsumed = true // one track per swipe
            } else if !horizontalDominant, self.scrollAccumulator > 18, !vm.isOpen {
                vm.open(); self.scrollAccumulator = 0
            } else if !horizontalDominant, self.scrollAccumulator < -18, vm.isOpen, vm.tab != .clipboard, vm.tab != .notes {
                vm.close(); self.scrollAccumulator = 0
            }
            return event
        }
    }
}
