import AppKit
import Observation

enum NotchTab: String, CaseIterable, Identifiable {
    case home, shelf, clipboard, stats, timer
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .stats: "gauge.with.dots.needle.67percent"
        case .timer: "timer"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .stats: "System"
        case .timer: "Timer"
        }
    }
}

/// What the closed island is currently showing, in priority order.
enum CompactContent: Equatable {
    case idle
    case activity(TransientActivity)
    case music
    case timer

    var key: String {
        switch self {
        case .idle: "idle"
        case .activity(let a): "activity-\(a.kind)"
        case .music: "music"
        case .timer: "timer"
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

    @ObservationIgnored private var hoverWork: DispatchWorkItem?
    @ObservationIgnored private let prefs = Preferences.shared

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // MARK: Derived layout

    var isOpen: Bool { phase == .open }

    var compact: CompactContent {
        if let activity = ActivityCenter.shared.current { return .activity(activity) }
        if TimerService.shared.isRunning { return .timer }
        if prefs.musicActivity, NowPlayingService.shared.isPlaying { return .music }
        return .idle
    }

    var wingWidth: CGFloat {
        let h = geometry.notchSize.height
        switch compact {
        case .idle: return 0
        case .music: return h + 10
        case .timer: return 66
        case .activity(let a):
            switch a {
            case .volume, .brightness, .keyboardBacklight: return 108
            case .power, .lowBattery: return 86
            case .bluetooth: return 116
            case .shelf: return 58
            case .timerFinished: return 78
            case .nowPlayingChanged: return h + 10
            }
        }
    }

    /// Island size ignoring the hover "peek".
    private var baseShapeSize: CGSize {
        if isOpen {
            return CGSize(width: max(Metrics.openSize.width, geometry.notchSize.width + 360),
                          height: Metrics.openSize.height)
        }
        return CGSize(width: geometry.notchSize.width + wingWidth * 2, height: geometry.notchSize.height)
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
            let pad = Metrics.shadowPadding
            return CGSize(width: shape.width + pad * 2, height: shape.height + pad)
        }
        return CGSize(width: shape.width + Metrics.peekGrowth.width,
                      height: shape.height + Metrics.peekGrowth.height)
    }

    var topRadius: CGFloat { isOpen ? Metrics.openTopRadius : Metrics.closedTopRadius }
    var bottomRadius: CGFloat {
        if isOpen { return Metrics.openBottomRadius }
        return compact == .idle ? Metrics.closedBottomRadius : Metrics.closedBottomRadius + 2
    }

    // MARK: Intent

    func open(tab: NotchTab? = nil) {
        hoverWork?.cancel()
        if let tab { self.tab = tab }
        guard phase != .open else { return }
        phase = .open
        if prefs.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func close() {
        hoverWork?.cancel()
        guard phase != .closed else { return }
        phase = .closed
        isPinned = false
    }

    func toggle() { isOpen ? close() : open() }

    func setHovering(_ inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        hoverWork?.cancel()

        if inside {
            guard phase == .closed, prefs.openOnHover else { return }
            schedule(after: prefs.hoverDelay) { [weak self] in
                guard let self, self.isHovering else { return }
                self.open()
            }
        } else {
            guard phase == .open, prefs.closeOnMouseExit, !isPinned else { return }
            schedule(after: 0.16) { [weak self] in
                guard let self, !self.isHovering, !self.isPinned else { return }
                self.close()
            }
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
