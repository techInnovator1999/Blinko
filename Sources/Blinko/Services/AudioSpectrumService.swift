import AppKit
import CoreAudio
import Observation
import os

/// What the music bars show (Settings → Appearance → Visualizer).
enum VisualizerMode: String, CaseIterable, Identifiable {
    case off, classic, real
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .classic: String(localized: "Classic (animated)")
        case .real: String(localized: "Real (reacts to audio)")
        }
    }
}

/// Owns the system-audio tap behind the "Real" visualizer and turns it into spectra.
///
/// Event-driven and demand-based: spectrum views register while they are on screen and
/// the track is playing. The tap runs only while at least one does, the mode is Real,
/// the displays are awake and permission isn't denied; otherwise it is torn down and
/// nothing runs. FFTs are computed on the main thread at most once per display frame,
/// on request from a view's display link — never on the audio thread.
@MainActor
@Observable
final class AudioSpectrumService {
    static let shared = AudioSpectrumService()

    enum Status: Equatable {
        case idle         // nothing wants the tap
        case starting     // tap requested, no audio seen yet
        case live         // samples are arriving: draw the real spectrum
        case silent       // only digital silence for a while (muted app, prompt pending…)
        case denied       // System Audio Recording permission denied
        case unsupported  // macOS < 14.2
        case failed       // Core Audio refused the tap/aggregate
    }

    /// Views draw the real spectrum only while `.live`; every other state shows the
    /// classic animation, so failures and denial fall back seamlessly.
    private(set) var status: Status = .idle {
        didSet {
            if status != oldValue { Self.log.info("visualizer: \(String(describing: self.status), privacy: .public)") }
        }
    }
    private(set) var permission: AudioCapturePermission.Status = .unknown

    @ObservationIgnored nonisolated private static let log = Logger(subsystem: "app.blinko.Blinko", category: "visualizer")

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    /// Snapshot rendering: fixed band levels, drawn statically (no tap, no display link).
    @ObservationIgnored nonisolated(unsafe) static var previewLevels: [Float]?

    // MARK: Demand

    private struct Demand: Equatable { var bundleID: String?; var trackKey: String }
    @ObservationIgnored private var consumers: [ObjectIdentifier: Demand] = [:]
    @ObservationIgnored private var displaysAsleep = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // MARK: Capture (all Core Audio calls happen on `queue`)

    @ObservationIgnored private let queue = DispatchQueue(label: "app.blinko.audiotap", qos: .userInitiated)
    @ObservationIgnored private let ring = AudioSampleRing()
    @ObservationIgnored private var capture: AnyObject? // AudioTapCapture on 14.2+
    @ObservationIgnored private var running: (bundleID: String?, global: Bool)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sampleRate: Double = 48_000
    @ObservationIgnored private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var retargetWork: DispatchWorkItem?
    @ObservationIgnored private var stopWork: DispatchWorkItem?

    // MARK: Analysis

    @ObservationIgnored private let analyzer = SpectrumAnalyzer(size: 2048)
    @ObservationIgnored private let window = UnsafeMutablePointer<Float>.allocate(capacity: 2048)
    @ObservationIgnored private var lastAnalysis: CFTimeInterval = 0
    @ObservationIgnored private var startedAt: CFTimeInterval = 0
    @ObservationIgnored private var lastSignal: CFTimeInterval = 0

    private init() {
        window.initialize(repeating: 0, count: analyzer.size)
        permission = AudioCapturePermission.status
        if !Self.isSupported { status = .unsupported }
        let center = NSWorkspace.shared.notificationCenter
        let sleep: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let wake: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for name in sleep {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.displaysAsleep = true; self.reconcile() }
            })
        }
        for name in wake {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.displaysAsleep = false; self.reconcile() }
            })
        }
    }

    /// A spectrum view is on screen with the track playing (`active`), or no longer is.
    func setDemand(_ owner: AnyObject, active: Bool, bundleID: String?, trackKey: String) {
        let id = ObjectIdentifier(owner)
        let new = active ? Demand(bundleID: bundleID, trackKey: trackKey) : nil
        let old = consumers[id]
        guard old != new else { return }
        consumers[id] = new
        Self.log.debug("visualizer demand \(self.consumers.count) (\(active))")
        // A new track, or playback resuming, retries a tap that went silent or failed.
        if new != nil, status == .silent || status == .failed { stopCapture(); status = .idle }
        reconcile()
    }

    /// Settings changed (mode switched) — start or stop accordingly.
    func preferencesChanged() {
        if Preferences.shared.visualizerMode != .real { stopCapture() }
        reconcile()
    }

    /// Called when the user picks "Real": asks for System Audio Recording if undecided.
    func requestPermission() {
        guard Self.isSupported else { return }
        permission = AudioCapturePermission.status
        guard permission == .unknown else { reconcile(); return }
        AudioCapturePermission.request { granted in
            Task { @MainActor in
                let current = AudioCapturePermission.status
                self.permission = current != .unknown ? current : (granted == true ? .authorized : granted == false ? .denied : .unknown)
                if self.status == .denied || self.status == .silent { self.stopCapture(); self.status = .idle }
                self.reconcile()
            }
        }
    }

    private var wanted: Demand? {
        guard Preferences.shared.visualizerMode == .real, !displaysAsleep, Self.isSupported else { return nil }
        return consumers.values.first
    }

    private func reconcile() {
        guard Self.isSupported else { return }
        guard let demand = wanted else {
            // A short grace period lets a view swap (track-change peek, wing re-layout)
            // keep the running tap instead of tearing it down and rebuilding it.
            let immediate = Preferences.shared.visualizerMode != .real || displaysAsleep || capture == nil
            if immediate { stopNow() } else if stopWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.stopWork = nil
                    if self.wanted == nil { self.stopNow() }
                }
                stopWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
            }
            return
        }
        stopWork?.cancel()
        stopWork = nil
        if AudioCapturePermission.status == .denied {
            permission = .denied
            stopCapture()
            status = .denied
            return
        }
        if status == .silent || status == .failed { return } // wait for the next track / play
        if let running, running.bundleID == demand.bundleID { return }
        startCapture(bundleID: demand.bundleID, global: false)
    }

    private func stopNow() {
        stopWork?.cancel()
        stopWork = nil
        stopCapture()
        if status != .denied { status = .idle }
    }

    // MARK: Tap lifecycle

    private func startCapture(bundleID: String?, global: Bool) {
        guard #available(macOS 14.2, *) else { return }
        stopCapture()
        generation += 1
        let gen = generation
        running = (bundleID, global)
        if status != .live { status = .starting } // re-taps (new helper, new output) keep drawing
        startedAt = CACurrentMediaTime()
        lastSignal = 0
        let tap = AudioTapCapture(ring: ring)
        capture = tap
        queue.async {
            var target: AudioTapCapture.Target = .global
            if !global, let bundleID {
                let ids = AudioTapCapture.processObjects(for: bundleID)
                if !ids.isEmpty { target = .processes(ids) }
            }
            do {
                let began = CACurrentMediaTime()
                try tap.start(target)
                Self.log.info("visualizer tap start took \(Int((CACurrentMediaTime() - began) * 1000)) ms, preflight \(AudioCapturePermission.rawPreflight)")
                let rate = tap.sampleRate
                Self.log.info("""
                    visualizer tap on \(String(describing: target), privacy: .public) for \(bundleID ?? "-", privacy: .public), \
                    \(rate) Hz, permission \(String(describing: AudioCapturePermission.status), privacy: .public)
                    """)
                DispatchQueue.main.async {
                    guard self.generation == gen else { return }
                    self.sampleRate = rate
                    if case .processes = target, let bundleID { self.watchProcesses(bundleID: bundleID, gen: gen) }
                    self.watchDefaultOutput(gen: gen)
                }
            } catch {
                Self.log.error("visualizer tap failed: \(String(describing: error), privacy: .public)")
                DispatchQueue.main.async {
                    guard self.generation == gen else { return }
                    self.running = nil
                    self.capture = nil
                    self.status = .failed
                }
            }
        }
    }

    private func stopCapture() {
        removeListeners()
        retargetWork?.cancel()
        retargetWork = nil
        generation += 1
        running = nil
        lastAnalysis = 0
        guard let tap = capture else { return }
        capture = nil
        if #available(macOS 14.2, *), let tap = tap as? AudioTapCapture {
            queue.async { tap.stop() }
        }
    }

    /// Browsers spin up audio helper processes on demand: re-tap when the app's set changes.
    private func watchProcesses(bundleID: String, gen: Int) {
        guard #available(macOS 14.2, *) else { return }
        addListener(kAudioHardwarePropertyProcessObjectList) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.retargetWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == gen,
                      let tap = self.capture as? AudioTapCapture, case .processes(let current)? = tap.target else { return }
                self.queue.async {
                    let ids = AudioTapCapture.processObjects(for: bundleID)
                    guard !ids.isEmpty, ids != current else { return }
                    DispatchQueue.main.async {
                        guard self.generation == gen else { return }
                        self.startCapture(bundleID: bundleID, global: false)
                    }
                }
            }
            self.retargetWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func watchDefaultOutput(gen: Int) {
        addListener(kAudioHardwarePropertyDefaultSystemOutputDevice) { [weak self] in
            guard let self, self.generation == gen, let running = self.running else { return }
            self.startCapture(bundleID: running.bundleID, global: running.global)
        }
    }

    private func addListener(_ selector: AudioObjectPropertySelector, _ handler: @escaping @MainActor () -> Void) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            listeners.append((address, block))
        }
    }

    private func removeListeners() {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        listeners.removeAll()
    }

    // MARK: Frames

    /// Latest spectrum for a display-link tick; analysed at most once per ~frame however
    /// many views ask. Also drives the live/silent state machine.
    func spectrum(at time: CFTimeInterval) -> (power: UnsafeBufferPointer<Float>, peak: Float, sampleRate: Double)? {
        guard running != nil, capture != nil else { return nil }
        if time - lastAnalysis > 0.012 {
            lastAnalysis = time
            ring.copyLatest(analyzer.size, into: window)
            analyzer.analyze(window)
            updateSignalState(time)
        }
        return analyzer.power.withUnsafeBufferPointer { ($0, analyzer.peak, sampleRate) }
    }

    /// Exact zeros mean nothing reaches the tap: wrong processes (retry system-wide), the
    /// permission prompt still open, or the app muted. Quiet music is never exactly 0.
    /// Once live, silence (gaps between tracks) just lets the bars fall.
    private func updateSignalState(_ time: CFTimeInterval) {
        if analyzer.peak > 0 {
            lastSignal = time
            if status != .live { status = .live }
            return
        }
        guard lastSignal == 0, let running else { return }
        let quietFor = time - startedAt
        if !running.global, quietFor > 3 {
            startCapture(bundleID: running.bundleID, global: true)
        } else if running.global, quietFor > 6 {
            stopCapture()
            status = AudioCapturePermission.status == .denied ? .denied : .silent
        }
    }
}
