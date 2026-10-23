import AppKit
import SwiftUI
import os

private let log = Logger(subsystem: "app.blinko.Blinko", category: "lockscreen")

/// Shows the islands (and the optional widget panel) on the lock screen.
///
/// While unlocked it does nothing beyond a handful of notification observers, and only when
/// the feature is on. On lock it moves the island panels into `SkyLightSpace` (absolute level
/// above the lock screen) and switches their view models to lock-screen mode; on unlock it
/// waits for the lock screen to fade, takes them out again and restores every window property
/// it touched, then checks the window server really shows them (recreating the islands if not).
@MainActor
final class LockScreenController {
    static let shared = LockScreenController()

    /// The screen is locked (as far as the notifications told us).
    private(set) var isLocked = false
    /// Island windows are in the lock-screen space (from lock until shortly after unlock).
    private(set) var isEngaged = false

    struct SavedState {
        weak var window: NSWindow?
        let level: NSWindow.Level
        let collectionBehavior: NSWindow.CollectionBehavior
        let canBecomeVisibleWithoutLogin: Bool
        let alphaValue: CGFloat
        let ignoresMouseEvents: Bool
    }

    private weak var manager: NotchManager?
    private let settings = LockScreenSettings.shared
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var saved: [ObjectIdentifier: SavedState] = [:]
    private var engagedModels: [WeakViewModel] = []
    private var widgetPanel: LockScreenWidgetPanel?
    private var releaseWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var sawSessionLocked = false

    private struct WeakViewModel { weak var vm: NotchViewModel? }

    /// Delay between unlock and leaving the lock-screen space: the lock screen fades out for
    /// ~0.4 s, and dropping the island below it earlier would make it blink.
    static let releaseDelay: TimeInterval = 0.6

    func attach(_ manager: NotchManager) {
        self.manager = manager
        manager.onIslandsRebuilt = { [weak self] in self?.islandsRebuilt() }
        syncObservers()
    }

    // MARK: Observers (only while the feature is on)

    private func syncObservers() {
        withObservationTracking {
            _ = settings.enabled
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.syncObservers() }
        }
        let wanted = settings.enabled && SkyLightSpace.shared.isAvailable
        if wanted, observers.isEmpty {
            installObservers()
        } else if !wanted, !observers.isEmpty {
            removeObservers()
            if isLocked || isEngaged { unlocked(immediately: true) }
        }
    }

    private func installObservers() {
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, "com.apple.screenIsLocked") { $0.locked() }
        observe(dnc, "com.apple.screenIsUnlocked") { $0.unlocked(immediately: false) }
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.screensDidSleepNotification.rawValue) { $0.screensSlept() }
        observe(ws, NSWorkspace.screensDidWakeNotification.rawValue) { $0.screensWoke() }
        // Fast user switching: our windows can't be seen from another session; leave cleanly.
        observe(ws, NSWorkspace.sessionDidResignActiveNotification.rawValue) { $0.unlocked(immediately: true) }
        // Fallback for a late / missed screenIsUnlocked.
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification.rawValue) { me in
            if me.isLocked, Self.sessionScreenIsLocked() != true { me.unlocked(immediately: false) }
        }
        log.info("lock-screen observers installed")
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ handler: @escaping @MainActor (LockScreenController) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handler(self) } }
        }
        observers.append((center, token))
    }

    private func removeObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }

    // MARK: Lock

    private func locked() {
        guard settings.enabled, !isLocked else { return }
        isLocked = true
        releaseWork?.cancel()
        releaseWork = nil
        guard SkyLightSpace.shared.show() else { return }
        log.info("screen locked: moving islands to the lock screen")
        isEngaged = true
        if settings.showIsland {
            manager?.islandControllers.forEach(engage)
        }
        if settings.showWidgets { showWidgets() }
        startPolling()
    }

    private func engage(_ controller: NotchWindowController) {
        let vm = controller.viewModel
        vm.close()
        vm.lockScreenMode = true
        if !engagedModels.contains(where: { $0.vm === vm }) { engagedModels.append(WeakViewModel(vm: vm)) }
        delegate(controller.panel)
    }

    /// Saves what we change, makes the window visible without login and moves it into the space.
    private func delegate(_ window: NSWindow, alpha: CGFloat = 1) {
        let key = ObjectIdentifier(window)
        if saved[key] == nil { saved[key] = Self.capture(window) }
        Self.moveToLockSpace(window, alpha: alpha)
    }

    static func capture(_ window: NSWindow) -> SavedState {
        SavedState(window: window, level: window.level, collectionBehavior: window.collectionBehavior,
                   canBecomeVisibleWithoutLogin: window.canBecomeVisibleWithoutLogin,
                   alphaValue: window.alphaValue, ignoresMouseEvents: window.ignoresMouseEvents)
    }

    @discardableResult
    static func moveToLockSpace(_ window: NSWindow, alpha: CGFloat = 1) -> Bool {
        window.canBecomeVisibleWithoutLogin = true
        window.alphaValue = alpha // islands may have been hidden for a fullscreen app
        window.ignoresMouseEvents = false
        if window.windowNumber <= 0 { window.orderFrontRegardless() }
        let moved = SkyLightSpace.shared.add(window)
        window.orderFrontRegardless()
        return moved
    }

    /// Displays changed while locked: new islands join the lock screen too.
    private func islandsRebuilt() {
        guard isLocked, isEngaged, settings.showIsland else { return }
        manager?.islandControllers.forEach(engage)
        if let panel = widgetPanel, panel.isVisible { panel.place() }
    }

    // MARK: Unlock

    private func unlocked(immediately: Bool) {
        guard isLocked || isEngaged else { return }
        let wasLocked = isLocked
        isLocked = false
        stopPolling()
        if wasLocked { log.info("screen unlocked") }
        hideWidgets()
        for entry in engagedModels {
            entry.vm?.close()
            entry.vm?.lockScreenMode = false
        }
        engagedModels.removeAll()
        releaseWork?.cancel()
        if immediately {
            release()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.release() }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay, execute: work)
        }
    }

    /// Takes every window out of the space and restores exactly what `delegate` changed.
    private func release() {
        releaseWork = nil
        guard !isLocked else { return } // locked again during the delay
        if let panel = widgetPanel {
            panel.orderOut(nil)
            panel.contentView = nil // no SwiftUI work while unlocked
        }
        // Islands torn down while locked (display unplugged) are only taken out of the space,
        // never ordered back in.
        let live = Set((manager?.islandControllers ?? []).map { ObjectIdentifier($0.panel) })
        var restored: [NSWindow] = []
        for (key, state) in saved {
            guard let window = state.window else { continue }
            let isLiveIsland = live.contains(key)
            Self.restore(window, state, reorder: isLiveIsland)
            if isLiveIsland { restored.append(window) }
        }
        saved.removeAll()
        SkyLightSpace.shared.hide()
        isEngaged = false
        log.info("islands back on the desktop")
        verifyVisible(restored)
    }

    static func restore(_ window: NSWindow, _ state: SavedState, reorder: Bool) {
        SkyLightSpace.shared.remove(window)
        // Re-assigning the collection behaviour makes AppKit re-register the window's space
        // tags (sticky / all spaces) with the window server.
        window.collectionBehavior = []
        window.collectionBehavior = state.collectionBehavior
        window.level = state.level
        window.canBecomeVisibleWithoutLogin = state.canBecomeVisibleWithoutLogin
        window.alphaValue = state.alphaValue
        window.ignoresMouseEvents = state.ignoresMouseEvents
        if reorder { window.orderFrontRegardless() }
    }

    /// The window server must list every restored island as on screen; if one went missing
    /// (left in no space), recreate the islands rather than leave the user without one.
    private func verifyVisible(_ windows: [NSWindow]) {
        let numbers = windows.map(\.windowNumber).filter { $0 > 0 }
        guard !numbers.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isLocked, !self.isEngaged else { return }
            let onscreen = Self.onscreenWindowNumbers()
            let missing = numbers.filter { !onscreen.contains($0) }
            guard !missing.isEmpty else { return }
            log.error("\(missing.count) island(s) not on screen after unlock; recreating")
            self.manager?.recreateIslands()
        }
    }

    static func onscreenWindowNumbers() -> Set<Int> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        return Set(info.compactMap { w in
            (w[kCGWindowOwnerPID as String] as? Int) == pid ? w[kCGWindowNumber as String] as? Int : nil
        })
    }

    // MARK: Display sleep

    private func screensSlept() {
        guard isEngaged else { return }
        widgetPanel?.orderOut(nil)
    }

    private func screensWoke() {
        if !isLocked, Self.sessionScreenIsLocked() == true, settings.enabled {
            locked() // locked while asleep and the notification was missed
            return
        }
        guard isLocked, isEngaged else { return }
        // Re-assert membership: some macOS versions reshuffle spaces on wake.
        for (_, state) in saved {
            guard let window = state.window, window !== widgetPanel else { continue }
            SkyLightSpace.shared.add(window)
            window.orderFrontRegardless()
        }
        if settings.showWidgets { showWidgets() }
    }

    // MARK: Widget panel

    private func showWidgets() {
        let panel = widgetPanel ?? LockScreenWidgetPanel()
        widgetPanel = panel
        if panel.contentView == nil { panel.installContent() }
        panel.place()
        delegate(panel, alpha: 0)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    private func hideWidgets() {
        guard let panel = widgetPanel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }
    }

    // MARK: Missed-unlock fallback

    /// `CGSSessionScreenIsLocked` from the session dictionary (undocumented key; nil if absent).
    static func sessionScreenIsLocked() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        return session["CGSSessionScreenIsLocked"] as? Bool
    }

    /// While locked only: every 3 s, check the session flag in case the unlock notification
    /// never arrives. It only acts after it has seen the flag set during this lock, so a
    /// missing key can never unlock us by mistake.
    private func startPolling() {
        stopPolling()
        sawSessionLocked = Self.sessionScreenIsLocked() == true
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isLocked else { return }
                let locked = Self.sessionScreenIsLocked()
                if locked == true { self.sawSessionLocked = true }
                if self.sawSessionLocked, locked != true { self.unlocked(immediately: false) }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

/// Borderless, click-through-free panel holding the lock-screen widgets. Created on the first
/// lock; its SwiftUI content exists only while the screen is locked.
final class LockScreenWidgetPanel: NSPanel {
    static let size = CGSize(width: 840, height: LockScreenWidgetsView.cardHeight + 24)

    init() {
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    @MainActor
    func installContent() {
        let hosting = FirstClickHostingView(rootView: LockScreenWidgetsView())
        hosting.sizingOptions = []
        contentView = hosting
    }

    /// Centred horizontally on the primary display (where the lock screen asks for the
    /// password), just below the middle so it clears the big clock and the login field.
    @MainActor
    func place() {
        guard let screen = NSScreen.screens.first else { return }
        let f = screen.frame
        let width = min(Self.size.width, f.width - 40)
        let y = f.midY - 40 - Self.size.height + CGFloat(LockScreenSettings.shared.widgetOffset)
        setFrame(CGRect(x: (f.midX - width / 2).rounded(), y: y.rounded(), width: width, height: Self.size.height),
                 display: false)
    }
}

/// Buttons work on the first click, without the panel being key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
