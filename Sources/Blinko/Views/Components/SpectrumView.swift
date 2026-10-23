import AppKit
import SwiftUI

// MARK: - SwiftUI entry points

/// The music bars in the closed island: Classic (render-server animation) or Real (the
/// audio spectrum, falling back to Classic until/unless real audio arrives).
struct MusicVisualizer: View {
    var isPlaying: Bool
    var color: NSColor
    var barCount = 4

    var body: some View {
        let mode = Preferences.shared.visualizerMode
        if mode == .real, let preview = AudioSpectrumService.previewLevels {
            StaticSpectrumBars(levels: SpectrumView.resample(preview, to: barCount), color: Color(nsColor: color),
                               style: .compact)
        } else if mode == .real {
            SpectrumView(style: .compact, barCount: barCount, color: color)
        } else {
            AudioVisualizer(isPlaying: isPlaying, color: color, barCount: barCount)
        }
    }
}

/// Subtle full spectrum along the bottom of the expanded player's artwork. Only in Real
/// mode with the option on; invisible (and idle) whenever there is no live audio.
struct ArtworkSpectrum: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        let prefs = Preferences.shared
        if prefs.visualizerMode == .real, prefs.expandedSpectrum {
            let preview = AudioSpectrumService.previewLevels
            let live = preview != nil || (AudioSpectrumService.shared.status == .live && NowPlayingService.shared.isPlaying)
            ZStack(alignment: .bottom) {
                scrim.opacity(live ? 1 : 0)
                Group {
                    if let preview {
                        StaticSpectrumBars(levels: SpectrumView.resample(preview, to: 24), color: .white, style: .expanded)
                    } else {
                        SpectrumView(style: .expanded, barCount: 24, color: .white)
                    }
                }
                .frame(height: 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(Motion.content, value: live)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .allowsHitTesting(false)
        }
    }

    private var scrim: some View {
        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            .frame(height: 44)
    }
}

/// Bridges a `SpectrumNSView` with the now-playing state. Reading `status` here makes
/// SwiftUI push live/fallback transitions into the view.
struct SpectrumView: NSViewRepresentable {
    var style: SpectrumNSView.Style
    var barCount: Int
    var color: NSColor

    func makeNSView(context: Context) -> SpectrumNSView {
        SpectrumNSView(style: style, barCount: barCount)
    }

    func updateNSView(_ view: SpectrumNSView, context: Context) {
        let np = NowPlayingService.shared
        view.update(.init(playing: np.isPlaying, color: color, status: AudioSpectrumService.shared.status,
                          bundleID: np.bundleID, trackKey: np.title + "\u{1F}" + np.artist))
    }

    static func dismantleNSView(_ view: SpectrumNSView, coordinator: ()) { view.teardown() }

    /// Max-pools (or repeats) `levels` to `count` values, for static previews.
    static func resample(_ levels: [Float], to count: Int) -> [Float] {
        guard !levels.isEmpty, count > 0 else { return [Float](repeating: 0, count: max(count, 0)) }
        return (0..<count).map { i in
            let a = i * levels.count / count
            let b = max(a + 1, (i + 1) * levels.count / count)
            return levels[a..<min(b, levels.count)].max() ?? 0
        }
    }
}

/// Static bars for `--snapshot` (ImageRenderer can't draw AppKit views).
struct StaticSpectrumBars: View {
    let levels: [Float]
    let color: Color
    let style: SpectrumNSView.Style

    var body: some View {
        GeometryReader { geo in
            let layout = SpectrumNSView.layout(style: style, count: levels.count, size: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(levels.indices, id: \.self) { i in
                    let h = layout.height(for: CGFloat(levels[i]), in: geo.size.height)
                    Capsule()
                        .fill(color.opacity(style == .expanded ? 0.85 : 1))
                        .frame(width: layout.width, height: h)
                        .position(x: layout.x(i) , y: style == .compact ? geo.size.height / 2
                                                                      : geo.size.height - layout.inset - h / 2)
                }
            }
        }
    }
}

// MARK: - AppKit view

/// CALayer bars. In Real mode a display link (≤ 30 fps) runs only while the view is on
/// screen, the track plays and the tap is starting/live; each tick asks the shared
/// service for the latest spectrum and sets the bar heights without implicit animation.
/// Without live audio the compact style shows the Classic render-server animation and
/// the expanded style hides, so the app does no per-frame work.
final class SpectrumNSView: NSView {
    enum Style: Equatable { case compact, expanded }

    struct State: Equatable {
        var playing: Bool
        var color: NSColor
        var status: AudioSpectrumService.Status
        var bundleID: String?
        var trackKey: String
    }

    let style: Style
    private var bars: [CALayer] = []
    private var bands: SpectrumBands
    private var state: State?
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var classic: Bool? // nil = neither animation installed
    private var drawingLive = false
    private var windowObservers: [NSObjectProtocol] = []
    private var alphaObservation: NSKeyValueObservation?

    init(style: Style, barCount: Int) {
        self.style = style
        bands = SpectrumBands(count: barCount)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.anchorPoint = style == .compact ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 0.5, y: 0)
            bar.transform = CATransform3DMakeScale(1, Self.restScale(style), 1)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        if style == .expanded { layer?.opacity = 0 }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    struct Layout {
        let width: CGFloat
        let gap: CGFloat
        let inset: CGFloat
        let origin: CGFloat
        func x(_ i: Int) -> CGFloat { origin + CGFloat(i) * (width + gap) + width / 2 }
        func height(for level: CGFloat, in total: CGFloat) -> CGFloat {
            let usable = total - inset
            return max(width, usable * max(SpectrumNSView.restScale(gapStyle), level))
        }
        fileprivate var gapStyle: Style
    }

    static func restScale(_ style: Style) -> CGFloat { style == .compact ? 0.25 : 0.06 }

    static func layout(style: Style, count: Int, size: CGSize) -> Layout {
        let n = CGFloat(max(count, 1))
        switch style {
        case .compact:
            let gap: CGFloat = 2
            let w = max(1.5, (size.width - gap * (n - 1)) / n)
            return Layout(width: w, gap: gap, inset: 0, origin: 0, gapStyle: style)
        case .expanded:
            let side: CGFloat = 9, inset: CGFloat = 7 // inset: above the artwork edge
            let gap: CGFloat = 1.5
            let w = max(1, (size.width - side * 2 - gap * (n - 1)) / n)
            return Layout(width: w, gap: gap, inset: inset, origin: side, gapStyle: style)
        }
    }

    override func layout() {
        super.layout()
        let l = Self.layout(style: style, count: bars.count, size: bounds.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            let full = style == .compact ? bounds.height : max(0, bounds.height - l.inset)
            bar.bounds = CGRect(x: 0, y: 0, width: l.width, height: full)
            bar.position = CGPoint(x: l.x(i), y: style == .compact ? bounds.midY : l.inset)
            bar.cornerRadius = l.width / 2
        }
        CATransaction.commit()
    }

    // MARK: State

    func update(_ new: State) {
        if state?.color != new.color {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            let color = style == .expanded ? new.color.withAlphaComponent(0.85) : new.color
            bars.forEach { $0.backgroundColor = color.cgColor }
            CATransaction.commit()
        }
        state = new
        refresh()
    }

    func teardown() {
        stopLink()
        AudioSpectrumService.shared.setDemand(self, active: false, bundleID: nil, trackKey: "")
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        alphaObservation = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        alphaObservation = nil
        if let window {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
            alphaObservation = window.observe(\.alphaValue) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        refresh()
    }

    override func viewDidHide() { super.viewDidHide(); refresh() }
    override func viewDidUnhide() { super.viewDidUnhide(); refresh() }

    private var isOnScreen: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        return window.occlusionState.contains(.visible) && window.alphaValue > 0.01
    }

    private func refresh() {
        guard let state else { return }
        let onScreen = isOnScreen
        let demand = onScreen && state.playing
        AudioSpectrumService.shared.setDemand(self, active: demand, bundleID: state.bundleID, trackKey: state.trackKey)
        let tapActive = demand && (state.status == .live || state.status == .starting)
        let live = tapActive && state.status == .live

        if live != drawingLive {
            drawingLive = live
            if live { removeClassic() }
            if style == .expanded {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.35)
                layer?.opacity = live ? 1 : 0
                CATransaction.commit()
            }
        }
        if tapActive {
            startLink()
        } else if !drawingLive {
            stopLink()
            bands.reset()
        }
        if style == .compact && !live { setClassic(playing: state.playing && onScreen) }
    }

    // MARK: Classic fallback (compact only)

    private func setClassic(playing: Bool) {
        guard classic != playing else { return }
        classic = playing
        VisualizerNSView.applyClassic(to: bars, playing: playing)
    }

    private func removeClassic() {
        guard classic != nil else { return }
        classic = nil
        for bar in bars { bar.removeAllAnimations() }
    }

    // MARK: Display link

    private func startLink() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTick = 0
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTick == 0 ? 1.0 / 30 : min(0.1, max(0.001, now - lastTick))
        lastTick = now
        if let s = AudioSpectrumService.shared.spectrum(at: now) {
            bands.ingest(power: s.power, peak: s.peak, sampleRate: s.sampleRate, dt: dt)
        } else {
            bands.ingest(power: UnsafeBufferPointer(start: nil, count: 0), peak: 0, sampleRate: 48_000, dt: dt)
        }
        bands.smooth(dt: dt)
        guard drawingLive else { return }
        let rest = Self.restScale(style)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.transform = CATransform3DMakeScale(1, max(rest, CGFloat(bands.levels[i])), 1)
        }
        CATransaction.commit()
        // Paused or gone: once the bars have fallen, stop ticking.
        if let state, !(state.playing && isOnScreen), bands.isSettled { refresh() }
    }
}
