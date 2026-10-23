import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreAudio
import Observation

/// A keyboard shortcut posted to a meeting app (only when Accessibility is already granted).
struct KeyChord: Equatable {
    let key: Int
    let flags: CGEventFlags

    static func cmd(_ key: Int) -> KeyChord { KeyChord(key: key, flags: .maskCommand) }
    static func cmdShift(_ key: Int) -> KeyChord { KeyChord(key: key, flags: [.maskCommand, .maskShift]) }
}

/// An app whose microphone use counts as "in a call".
struct MeetingApp: Identifiable, Equatable {
    let id: String
    let name: String
    /// Bundle IDs of the app the user sees (icon, bring to front).
    let bundleIDs: [String]
    /// Prefixes matched against CoreAudio client bundle IDs (helper processes included).
    let audioPrefixes: [String]
    var isBrowser = false
    /// Leaves the call (Zoom asks to confirm). nil: Leave just brings the app to front.
    var leave: KeyChord?
    /// Toggles the app's own microphone mute.
    var toggleMute: KeyChord?

    static let catalog: [MeetingApp] = [
        MeetingApp(id: "zoom", name: "Zoom", bundleIDs: ["us.zoom.xos"], audioPrefixes: ["us.zoom."],
                   leave: .cmd(kVK_ANSI_W), toggleMute: .cmdShift(kVK_ANSI_A)),
        MeetingApp(id: "teams", name: "Microsoft Teams", bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"],
                   audioPrefixes: ["com.microsoft.teams"],
                   leave: .cmdShift(kVK_ANSI_H), toggleMute: .cmdShift(kVK_ANSI_M)),
        MeetingApp(id: "webex", name: "Webex", bundleIDs: ["Cisco-Systems.Spark", "com.webex.meetingmanager"],
                   audioPrefixes: ["Cisco-Systems.Spark", "com.webex."],
                   toggleMute: .cmdShift(kVK_ANSI_M)),
        MeetingApp(id: "facetime", name: "FaceTime", bundleIDs: ["com.apple.FaceTime"],
                   // FaceTime's audio runs in the avconferenced daemon.
                   audioPrefixes: ["com.apple.FaceTime", "com.apple.avconferenced"]),
        MeetingApp(id: "slack", name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"],
                   audioPrefixes: ["com.tinyspeck.slackmacgap"],
                   leave: .cmdShift(kVK_ANSI_H), toggleMute: .cmdShift(kVK_Space)),
        MeetingApp(id: "discord", name: "Discord", bundleIDs: ["com.hnc.Discord"], audioPrefixes: ["com.hnc.Discord"],
                   toggleMute: .cmdShift(kVK_ANSI_M)),
        MeetingApp(id: "browser", name: String(localized: "Browsers (Google Meet…)"),
                   bundleIDs: ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac",
                               "com.brave.Browser", "org.mozilla.firefox", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"],
                   audioPrefixes: ["com.google.Chrome", "com.apple.WebKit", "com.apple.Safari", "company.thebrowser",
                                   "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox",
                                   "com.operasoftware.Opera", "com.vivaldi.Vivaldi"],
                   isBrowser: true,
                   toggleMute: .cmd(kVK_ANSI_D)), // Google Meet's mute shortcut
    ]

    var symbol: String {
        switch id {
        case "zoom": "video.fill"
        case "facetime": "video.fill"
        case "browser": "globe"
        default: "phone.fill"
        }
    }
}

/// The call in progress.
struct ActiveCall: Equatable {
    let app: MeetingApp
    /// The running app shown to the user (for browsers: the browser that holds the mic).
    let bundleID: String
    let pid: pid_t
    let start: Date

    var displayName: String {
        guard app.isBrowser else { return app.name }
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? app.name
    }
}

/// Meeting mode: notices calls and offers mute / leave controls.
///
/// Detection is event-driven and needs no permission: CoreAudio's per-process objects
/// (`kAudioHardwarePropertyProcessObjectList`, macOS 14+) say exactly which app is capturing the
/// microphone. Listeners: the process list, `IsRunningInput/Output` of meeting-app processes,
/// NSWorkspace launch / terminate / activate. Nothing runs while Meeting mode is off.
/// If the process API is unavailable, "microphone in use + a meeting app running" is the fallback.
@MainActor
@Observable
final class MeetingService {
    static let shared = MeetingService()

    private(set) var call: ActiveCall?
    /// The default input device is muted (CoreAudio `kAudioDevicePropertyMute`): silences every app.
    private(set) var micMuted = false
    /// The meeting app reports itself muted: its mute menu item (Zoom, Accessibility) or it
    /// released the microphone while still playing call audio.
    private(set) var appMuted = false
    var isInCall: Bool { call != nil }
    var isMuted: Bool { micMuted || appMuted }

    @ObservationIgnored private var running = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var processListListener: AudioObjectPropertyListenerBlock?
    /// Meeting-app audio clients we listen to, keyed by CoreAudio process object.
    @ObservationIgnored private var clients: [AudioObjectID: (bundleID: String, pid: pid_t, block: AudioObjectPropertyListenerBlock)] = [:]
    @ObservationIgnored private var processAPIAvailable = true
    @ObservationIgnored private var evaluateScheduled = false
    @ObservationIgnored private var muteDevice = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var muteListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var defaultInputListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var appMuteProbe: Timer?
    @ObservationIgnored private var releasedMic = false
    @ObservationIgnored private var probedMuted = false
    @ObservationIgnored private var lastWarning = Date.distantPast
    @ObservationIgnored private var previewing = false

    private var prefs: Preferences { .shared }

    func refresh() {
        prefs.meetingMode ? start() : stop()
        updateDetector()
    }

    // MARK: Lifecycle

    private func start() {
        guard !running, !previewing else { return }
        running = true

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // App switches/launches only matter while the mic is live or a call is up;
                    // skipping them otherwise keeps everyday app switching free.
                    guard let self, self.call != nil || PrivacyService.shared.micInUse else { return }
                    self.scheduleEvaluate()
                }
            })
        }

        var list = Self.address(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reattachClients() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &list, .main, block) == noErr {
            processListListener = block
            processAPIAvailable = true
        } else {
            processAPIAvailable = false
        }
        reattachClients()
        observeFallback()
    }

    private func stop() {
        guard running else { return }
        running = false
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        if let block = processListListener {
            var list = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &list, .main, block)
            processListListener = nil
        }
        detachClients()
        setCall(nil)
    }

    /// Without the process API, the privacy service's microphone listener drives evaluation.
    private func observeFallback() {
        guard running, !processAPIAvailable else { return }
        withObservationTracking { _ = PrivacyService.shared.micInUse } onChange: { [weak self] in
            DispatchQueue.main.async { self?.scheduleEvaluate(); self?.observeFallback() }
        }
    }

    // MARK: CoreAudio clients

    private func reattachClients() {
        guard running, processAPIAvailable else { return scheduleEvaluate() }
        let objects = Self.processObjects()
        let current = Set(objects)
        for (object, client) in clients where !current.contains(object) {
            removeClientListeners(object, client.block)
            clients[object] = nil
        }
        for object in objects where clients[object] == nil {
            guard let bundleID = Self.bundleID(of: object),
                  MeetingApp.catalog.contains(where: { app in app.audioPrefixes.contains { bundleID.hasPrefix($0) } })
            else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleEvaluate() }
            }
            for selector in [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput] {
                var addr = Self.address(selector)
                AudioObjectAddPropertyListenerBlock(object, &addr, .main, block)
            }
            clients[object] = (bundleID, Self.pid(of: object), block)
        }
        scheduleEvaluate()
    }

    private func detachClients() {
        for (object, client) in clients { removeClientListeners(object, client.block) }
        clients.removeAll()
    }

    private func removeClientListeners(_ object: AudioObjectID, _ block: @escaping AudioObjectPropertyListenerBlock) {
        for selector in [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput] {
            var addr = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(object, &addr, .main, block)
        }
    }

    // MARK: Evaluation

    /// Coalesces bursts (a call start fires several listeners at once) into one pass.
    private func scheduleEvaluate() {
        guard running, !evaluateScheduled else { return }
        evaluateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.evaluateScheduled = false
            self.evaluate()
        }
    }

    private func evaluate() {
        guard running else { return }
        let enabled = MeetingApp.catalog.filter { !prefs.disabledMeetingApps.contains($0.id) }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        var found: (app: MeetingApp, host: NSRunningApplication)?
        var released = false

        if processAPIAvailable {
            var capturing: [(MeetingApp, NSRunningApplication)] = []
            var playingCurrent = false
            for (object, client) in clients {
                guard let (app, host) = Self.resolve(client.bundleID, pid: client.pid, in: enabled) else { continue }
                if Self.flag(object, kAudioProcessPropertyIsRunningInput) {
                    capturing.append((app, host))
                } else if app == call?.app, Self.flag(object, kAudioProcessPropertyIsRunningOutput) {
                    playingCurrent = true
                }
            }
            if let pick = capturing.first(where: { $0.1.bundleIdentifier == frontmost })
                ?? capturing.first(where: { $0.0 == call?.app }) ?? capturing.first {
                found = pick
            } else if let current = call, !current.app.isBrowser, playingCurrent,
                      let host = NSRunningApplication(processIdentifier: current.pid), !host.isTerminated {
                // Mic released but call audio still playing: the app muted itself by closing
                // the input (browsers excluded: another tab may be playing).
                found = (current.app, host)
                released = true
            }
        } else if PrivacyService.shared.micInUse {
            let apps = NSWorkspace.shared.runningApplications
            let candidates: [(MeetingApp, NSRunningApplication)] = apps.compactMap { running in
                guard let id = running.bundleIdentifier,
                      let app = enabled.first(where: { $0.bundleIDs.contains(id) }) else { return nil }
                return (app, running)
            }
            found = candidates.first(where: { $0.1.bundleIdentifier == frontmost }) ?? candidates.first
        }

        if let found {
            let keep = call.map { $0.app == found.app && $0.pid == found.host.processIdentifier } ?? false
            if !keep {
                setCall(ActiveCall(app: found.app, bundleID: found.host.bundleIdentifier ?? "",
                                   pid: found.host.processIdentifier, start: call?.app == found.app ? call!.start : .now))
            }
        } else {
            setCall(nil)
        }
        releasedMic = released
        updateAppMuted()
    }

    /// Maps a CoreAudio client to a meeting app and the running app the user sees.
    private static func resolve(_ bundleID: String, pid: pid_t, in apps: [MeetingApp]) -> (MeetingApp, NSRunningApplication)? {
        guard let app = apps.first(where: { $0.audioPrefixes.contains { bundleID.hasPrefix($0) } }) else { return nil }
        let running = NSWorkspace.shared.runningApplications
        // Helpers (and shared daemons such as WebKit's GPU process or avconferenced) belong to
        // the meeting app's main process; for a direct match, the process itself.
        if let direct = NSRunningApplication(processIdentifier: pid), let id = direct.bundleIdentifier,
           app.bundleIDs.contains(id) {
            return (app, direct)
        }
        let hostIDs: [String]
        if bundleID.hasPrefix("com.apple.WebKit") {
            hostIDs = ["com.apple.Safari"] // other WebKit apps (Mail…) don't count
        } else {
            // Browsers: the one whose helper this is ("com.google.Chrome.helper" → Chrome).
            let lower = bundleID.lowercased()
            hostIDs = app.bundleIDs.filter { !app.isBrowser || lower.hasPrefix($0.lowercased()) }
        }
        guard let host = running.first(where: { ($0.bundleIdentifier).map(hostIDs.contains) ?? false }) else { return nil }
        return (app, host)
    }

    private func setCall(_ new: ActiveCall?) {
        guard new != call else { return }
        let wasInCall = call != nil
        call = new
        if new == nil {
            releasedMic = false
            probedMuted = false
            appMuted = false
        }
        if (new != nil) != wasInCall {
            new != nil ? attachMuteListener() : detachMuteListener()
        }
        updateAppMuteProbe()
        updateDetector()
    }

    // MARK: Mute (system input)

    func toggleMute() {
        setMicMuted(!micMuted)
    }

    func setMicMuted(_ muted: Bool) {
        AudioLevels.setMuted(.input, muted)
        micMuted = AudioLevels.isMuted(.input)
        updateDetector()
    }

    /// Unmutes wherever the mute is: the system input and/or the meeting app (its own shortcut,
    /// posted only with Accessibility; otherwise the app is brought to the front).
    func unmuteEverywhere() {
        if micMuted { setMicMuted(false) }
        guard appMuted, let call else { return }
        if let shortcut = call.app.toggleMute, AXIsProcessTrusted() {
            post(shortcut, to: call)
        } else {
            bringToFront()
        }
    }

    private func attachMuteListener() {
        detachMuteListener()
        muteDevice = AudioLevels.defaultDevice(.input)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.micMuted = AudioLevels.isMuted(.input)
                self.updateDetector()
            }
        }
        var mute = AudioLevels.muteAddress(.input)
        if AudioObjectAddPropertyListenerBlock(muteDevice, &mute, .main, block) == noErr { muteListener = block }
        let defBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachMuteListener() }
        }
        var def = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &def, .main, defBlock) == noErr {
            defaultInputListener = defBlock
        }
        micMuted = AudioLevels.isMuted(.input)
    }

    private func detachMuteListener() {
        if let block = muteListener, muteDevice != kAudioObjectUnknown {
            var mute = AudioLevels.muteAddress(.input)
            AudioObjectRemovePropertyListenerBlock(muteDevice, &mute, .main, block)
        }
        if let block = defaultInputListener {
            var def = Self.address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &def, .main, block)
        }
        muteListener = nil
        defaultInputListener = nil
        muteDevice = AudioObjectID(kAudioObjectUnknown)
        micMuted = false
    }

    // MARK: App-level mute

    private func updateAppMuted() {
        let muted = call != nil && (releasedMic || probedMuted)
        guard muted != appMuted else { return }
        appMuted = muted
        updateDetector()
    }

    /// Zoom keeps the microphone open while muted; its "Mute / Unmute Audio" menu item is the
    /// only permission-light signal. Read through Accessibility (only if already granted), every
    /// 2 s, only during a Zoom call with the muted warning on. English menu titles only.
    private func updateAppMuteProbe() {
        let wanted = call?.app.id == "zoom" && prefs.mutedWarning && AXIsProcessTrusted()
        if wanted, appMuteProbe == nil {
            let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.probeAppMute() }
            }
            t.tolerance = 0.5
            RunLoop.main.add(t, forMode: .common)
            appMuteProbe = t
            probeAppMute()
        } else if !wanted, let t = appMuteProbe {
            t.invalidate()
            appMuteProbe = nil
            probedMuted = false
            updateAppMuted()
        }
    }

    private func probeAppMute() {
        guard let call else { return }
        probedMuted = Self.zoomMenuSaysMuted(pid: call.pid) ?? false
        updateAppMuted()
    }

    private static func zoomMenuSaysMuted(pid: pid_t) -> Bool? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar: AXUIElement = axValue(app, kAXMenuBarAttribute) else { return nil }
        for barItem in axChildren(bar) {
            for menu in axChildren(barItem) {
                for item in axChildren(menu) {
                    guard let title: String = axValue(item, kAXTitleAttribute) else { continue }
                    let t = title.lowercased()
                    if t.hasPrefix("unmute audio") { return true }
                    if t.hasPrefix("mute audio") { return false }
                }
            }
        }
        return nil
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        (axValue(element, kAXChildrenAttribute) as [AXUIElement]?) ?? []
    }

    // MARK: Muted warning

    /// The level meter runs only in the narrow case where it can work: in a call, muted *in
    /// the app* (the raw microphone still carries the voice), warning on, microphone access
    /// granted. A system-level (hardware) mute silences the input for every process, Blinko
    /// included, so speech can't be detected then.
    private func updateDetector() {
        let detector = MutedSpeechDetector.shared
        let wanted = running && prefs.mutedWarning && call != nil && appMuted && !micMuted
            && MutedSpeechDetector.isAuthorized
        if wanted {
            detector.onSpeech = { [weak self] in self?.speechWhileMuted() }
            detector.start()
        } else {
            detector.stop()
        }
    }

    private func speechWhileMuted() {
        guard isInCall, isMuted, Date().timeIntervalSince(lastWarning) > 8 else { return }
        lastWarning = Date()
        ActivityCenter.shared.show(.mutedWarning)
        if prefs.enableHaptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    func preferencesChanged() {
        updateAppMuteProbe()
        updateDetector()
        scheduleEvaluate()
    }

    // MARK: Actions

    var canLeave: Bool { call?.app.leave != nil && AXIsProcessTrusted() }

    func bringToFront() {
        guard let call, let app = NSRunningApplication(processIdentifier: call.pid), let url = app.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Best effort: the app's own "leave" shortcut when Accessibility is granted, otherwise
    /// just brings the call to the front.
    func leave() {
        guard let call else { return }
        if let shortcut = call.app.leave, AXIsProcessTrusted() {
            post(shortcut, to: call)
        } else {
            bringToFront()
        }
    }

    private func post(_ shortcut: KeyChord, to call: ActiveCall) {
        bringToFront()
        let pid = call.pid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.key), keyDown: down)
                event?.flags = shortcut.flags
                event?.postToPid(pid)
            }
        }
    }

    /// Calendar event happening now (started, or starting within 5 minutes).
    static func currentEvent(in items: [AgendaItem], now: Date = .now) -> AgendaItem? {
        items.first { !$0.isReminder && !$0.isAllDay && $0.start <= now.addingTimeInterval(300) && $0.end > now }
    }

    // MARK: CoreAudio helpers

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func bundleID(of object: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func pid(of object: AudioObjectID) -> pid_t {
        var addr = address(kAudioProcessPropertyPID)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &pid)
        return pid
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr && value != 0
    }

    // MARK: Preview

    /// Design-time state for snapshot rendering.
    func injectPreview(app id: String?, started: Date = .now, micMuted: Bool = false, appMuted: Bool = false) {
        previewing = true
        call = id.flatMap { id in MeetingApp.catalog.first { $0.id == id } }
            .map { ActiveCall(app: $0, bundleID: $0.bundleIDs[0], pid: -1, start: started) }
        self.micMuted = micMuted
        self.appMuted = appMuted
    }
}
