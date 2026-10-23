import AppKit
import Observation
import os

private let log = Logger(subsystem: "app.blinko.Blinko", category: "island")

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, stats, timer, notes, tools
    case agents
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .stats: "gauge.with.dots.needle.67percent"
        case .timer: "timer"
        case .notes: "note.text"
        case .tools: "eyedropper.halffull"
        case .agents: "sparkles.rectangle.stack.fill"
        }
    }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .shelf: String(localized: "Shelf")
        case .clipboard: String(localized: "Clipboard")
        case .stats: String(localized: "System")
        case .timer: String(localized: "Timer")
        case .notes: String(localized: "Notes")
        case .tools: String(localized: "Tools")
        case .agents: String(localized: "Agents")
        }
    }
}

/// What the closed island is currently showing, in priority order.
enum CompactContent: Equatable {
    case idle
    case activity(TransientActivity)
    case download
    case music
    case timer
    case privacy
    case clock
    case meeting
    case agent

    var key: String {
        switch self {
        case .idle: "idle"
        case .activity(let a): "activity-\(a.kind)"
        case .download: "download"
        case .music: "music"
        case .timer: "timer"
        case .privacy: "privacy"
        case .clock: "clock"
        case .meeting: "meeting"
        case .agent: "agent"
        }
    }
}

/// Per-display island state. Everything derived (sizes, radii) is computed so
/// SwiftUI only invalidates views that read the specific inputs that changed.
@MainActor
@Observable
final class NotchViewModel {
    enum Phase { case closed, open }

    private(set) var phase: Phase = .closed
    var tab: NotchTab = .home
    var geometry: NotchGeometry
    private(set) var isHovering = false
    var isDropTargeted = false
    var isPinned = false
    /// The panel is key because a text field is being edited (Notes): keep the island open.
    private(set) var isEditingText = false
    /// The colour sampler is up: the pointer leaves the island on purpose.
    var isSampling = false
    /// The command bar (⌥Space) replaces the tabs while it is up.
    private(set) var isCommandBarActive = false
    var holdsOpen: Bool { isPinned || isEditingText || isSampling || isCommandBarActive }
    /// The island is shown on the lock screen (LockScreenController): privacy-filtered
    /// compact content, no hover-open, tap expands the music player only.
    var lockScreenMode = false

    /// Wired by the window controller: make the panel key / hand keyboard focus back.
    @ObservationIgnored var requestKey: (() -> Void)?
    @ObservationIgnored var relinquishKey: (() -> Void)?
    /// Appearance preview / snapshots: a fixed closed-island state and no haptics.
    var compactOverride: CompactContent?
    @ObservationIgnored var isPreview = false

    @ObservationIgnored private var hoverWork: DispatchWorkItem?
    @ObservationIgnored private var requiresExitBeforeHoverOpen = false
    @ObservationIgnored private let prefs = Preferences.shared

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // MARK: Derived layout

    var isOpen: Bool { phase == .open }

    var compact: CompactContent {
        if let compactOverride { return compactOverride }
        if lockScreenMode { return lockScreenCompact }
        if let activity = ActivityCenter.shared.current { return .activity(activity) }
        if prefs.meetingMode, MeetingService.shared.isInCall { return .meeting }
        if prefs.agentCompact, AgentHubService.shared.hasActivity { return .agent }
        if DownloadsService.shared.active != nil { return .download }
        if TimerService.shared.hasRunning { return .timer }
        if prefs.musicActivity, NowPlayingService.shared.isPlaying { return .music }
        if prefs.privacyIndicators, PrivacyService.shared.anyInUse { return .privacy }
        if prefs.showClockWhenIdle { return .clock }
        return .idle
    }

    /// Camera / mic dots shown at the trailing edge on top of other compact content.
    var showsPrivacyEdge: Bool {
        let content = compact
        if case .activity(.privacy) = content { return false } // already shows them
        if case .activity(.mutedWarning) = content { return false } // needs the room
        return content != .idle && content != .privacy && content != .meeting
            && prefs.privacyIndicators && PrivacyService.shared.anyInUse
    }

    /// "Lyrics in closed island": the music wing widens once the track's lyrics are loaded.
    var showsCompactLyrics: Bool {
        guard prefs.compactLyrics, compact == .music else { return false }
        let np = NowPlayingService.shared
        return LyricsService.shared.hasLyrics(for: LyricsService.key(title: np.title, artist: np.artist))
    }

    var wingWidth: CGFloat {
        baseWingWidth + (showsPrivacyEdge ? 7 : 0)
    }

    private var baseWingWidth: CGFloat {
        let h = geometry.notchSize.height
        switch compact {
        case .idle: return 0
        case .music: return showsCompactLyrics ? 150 : h + 10
        case .download: return 76
        case .timer: return TimerService.shared.othersRunning > 0 ? 86 : 66
        case .privacy: return 40
        case .clock: return 76
        case .meeting: return PrivacyService.shared.cameraInUse ? 102 : 86
        case .agent: return AgentHubService.shared.approvals.isEmpty ? 118 : 124
        case .activity(let a):
            switch a {
            case .volume, .brightness, .keyboardBacklight, .microphone: return 108
            case .capsLock: return 100
            case .focusSession: return 96
            case .power, .lowBattery: return 86
            case .bluetooth(_, _, _, let battery): return battery == nil ? 116 : 138
            case .shelf: return 58
            case .timerFinished: return 78
            case .nowPlayingChanged: return h + 10
            case .focusMode: return 116
            case .privacy: return 108
            case .network: return 124
            case .downloadFinished: return 128
            case .mutedWarning: return 128
            case .custom(let alert): return alert.body == nil ? 120 : 150
            case .appNotification: return 160
            }
        }
    }

    /// Hardware notch width plus the user's fine-tune offset.
    var closedNotchWidth: CGFloat {
        max(80, geometry.notchSize.width + prefs.notchWidthOffset)
    }

    /// Island size ignoring the hover "peek".
    private var baseShapeSize: CGSize {
        if isOpen, lockScreenMode { return Metrics.lockScreenOpenSize(notchHeight: geometry.notchSize.height) }
        if isOpen {
            return CGSize(width: max(prefs.openWidth, geometry.notchSize.width + 360),
                          height: isCommandBarActive ? Metrics.commandBarHeight(rows: CommandBarModel.shared.results.count) : Theme.shared.openHeight)
        }
        return CGSize(width: closedNotchWidth + wingWidth * 2, height: geometry.notchSize.height)
    }

    var shapeSize: CGSize {
        var size = baseShapeSize
        if !isOpen, isHovering, compact == .idle || isDropTargeted {
            size.width += Metrics.peekGrowth.width
            size.height += Metrics.peekGrowth.height
        }
        return size
    }

    /// Window size needed to host the current state (plus shadow room when open).
    /// Deliberately independent of hover: resizing the window under the cursor would
    /// rebuild tracking areas and flip hover state, creating a feedback loop.
    var canvasSize: CGSize {
        let shape = baseShapeSize
        if isOpen {
            let pad = Theme.shared.shadowPadding
            return CGSize(width: shape.width + pad * 2, height: shape.height + pad)
        }
        return CGSize(width: shape.width + Metrics.peekGrowth.width,
                      height: shape.height + Metrics.peekGrowth.height)
    }

    var topRadius: CGFloat { isOpen ? Theme.shared.openTopRadius : Metrics.closedTopRadius }
    var bottomRadius: CGFloat {
        if isOpen { return Theme.shared.openBottomRadius }
        let closed = Theme.shared.closedBottomRadius
        return compact == .idle ? closed : closed + 2
    }

    // MARK: Hover hit-testing

    /// Whether a screen point (AppKit coordinates) is over the island. Computed from the
    /// island's geometry rather than tracking areas, so window resizes can never produce
    /// phantom enter/exit events. The open zone is larger than the shape (hysteresis), so
    /// the pointer can graze the edge without the island collapsing.
    func contains(screenPoint p: CGPoint) -> Bool {
        let screen = geometry.screenFrame
        let size = baseShapeSize
        let margin: (x: CGFloat, bottom: CGFloat) = isOpen ? (12, 16) : (6, 4)
        let halfWidth = size.width / 2 + margin.x
        return abs(p.x - screen.midX) <= halfWidth
            && p.y >= screen.maxY - size.height - margin.bottom
            && p.y <= screen.maxY + 1
    }

    // MARK: Intent

    func open(tab: NotchTab? = nil) {
        hoverWork?.cancel()
        if lockScreenMode, !lockScreenCanExpand { return }
        if let tab {
            self.tab = tab
        } else if phase == .closed, case .activity(.downloadFinished) = compact, prefs.visibleTabs.contains(.shelf) {
            // Opening on a finished download lands on the shelf, where it can be added.
            self.tab = .shelf
        } else if phase == .closed, compact == .agent {
            self.tab = .agents
        }
        guard phase != .open else { return }
        phase = .open
        log.info("open")
        if prefs.enableHaptics, !isPreview {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func close() {
        hoverWork?.cancel()
        guard phase != .closed else { return }
        phase = .closed
        log.info("close")
        isCommandBarActive = false
        isPinned = false
        isSampling = false
        if isEditingText { relinquishKey?() }
        // Closed deliberately while the pointer is still on the notch (swipe, hotkey, click):
        // don't hover-reopen until the pointer has left and come back.
        if isHovering { requiresExitBeforeHoverOpen = true }
    }

    func toggle() { isOpen ? close() : open() }

    /// Opens the island as a command bar and makes the panel key so typing goes to it.
    /// Pressing the shortcut again while it is up closes it.
    func toggleCommandBar() {
        if isOpen, isCommandBarActive { close(); return }
        isCommandBarActive = true
        open()
        requestKey?()
    }

    /// Leaves the command bar for a regular tab (Blinko actions such as "open shelf").
    func showTab(fromCommandBar tab: NotchTab) {
        // The panel stays key (so the island stays open) until the user clicks elsewhere.
        isCommandBarActive = false
        self.tab = tab
    }

    /// Pointer is inside but moving fast (passing through on the way to the menu bar):
    /// postpone opening until it settles, so sweeping across the notch never pops it open.
    func pointerPassingThrough() {
        guard isHovering, phase == .closed, prefs.openOnHover, !requiresExitBeforeHoverOpen else { return }
        armHoverOpen()
    }

    private func armHoverOpen() {
        guard !lockScreenMode else { return }
        schedule(after: max(prefs.hoverDelay, 0.06)) { [weak self] in
            guard let self, self.isHovering else { return }
            self.open()
        }
    }

    func setHovering(_ inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        log.debug("hover \(inside)")
        hoverWork?.cancel()

        if inside {
            guard phase == .closed, prefs.openOnHover, !requiresExitBeforeHoverOpen else { return }
            armHoverOpen()
        } else {
            requiresExitBeforeHoverOpen = false
            guard phase == .open, prefs.closeOnMouseExit, !holdsOpen else { return }
            schedule(after: 0.22) { [weak self] in
                guard let self, !self.isHovering, !self.holdsOpen else { return }
                self.close()
            }
        }
    }

    /// Called by the panel when it gains / loses key status (text editing). Losing it means
    /// the user clicked elsewhere: close if the pointer is no longer on the island.
    func panelKeyChanged(_ isKey: Bool) {
        guard isKey != isEditingText else { return }
        isEditingText = isKey
        if !isKey, phase == .open, !isHovering, prefs.closeOnMouseExit, !isPinned, !isSampling {
            close()
        } else if !isKey, isCommandBarActive {
            close() // clicked outside the command bar
        }
    }

    func dropTargetChanged(_ targeted: Bool) {
        isDropTargeted = targeted
        if targeted, prefs.shelfAutoOpenOnDrag { open(tab: .shelf) }
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
