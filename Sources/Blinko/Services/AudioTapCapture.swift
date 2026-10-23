import AppKit
import CoreAudio

/// System-audio capture with a Core Audio process tap (macOS 14.2+): a private, unmuted
/// mono tap on the now-playing app's processes (or on everything except Blinko), wrapped
/// in a private aggregate device whose IOProc only copies samples into `AudioSampleRing`.
/// Not thread-confined: the owner calls `start`/`stop` from one serial queue.
@available(macOS 14.2, *)
final class AudioTapCapture: @unchecked Sendable {
    enum Target: Equatable {
        case processes([AudioObjectID])
        case global
    }

    struct Failure: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "\(step) failed (\(status))" }
    }

    let ring: AudioSampleRing
    private(set) var sampleRate: Double = 48_000
    private(set) var target: Target?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init(ring: AudioSampleRing) { self.ring = ring }

    deinit { stop() }

    var isRunning: Bool { procID != nil }

    func start(_ target: Target) throws {
        stop()
        ring.clear()
        let description: CATapDescription
        switch target {
        case .processes(let ids):
            description = CATapDescription(monoMixdownOfProcesses: ids)
        case .global:
            let own = Self.processObject(pid: getpid()).map { [$0] } ?? []
            description = CATapDescription(monoGlobalTapButExcludeProcesses: own)
        }
        description.name = "Blinko Visualizer"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        description.uuid = UUID()

        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "AudioHardwareCreateProcessTap")
        tapID = tap

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "tap format")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else {
            stop()
            throw Failure(step: "tap format is not Float32", status: -1)
        }
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 48_000

        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Blinko Visualizer",
            kAudioAggregateDeviceUIDKey: "app.blinko.visualizer." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        // The default output as the clock source keeps the tap in step with playback.
        if let output = Self.defaultOutputUID() {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = output
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        do {
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "create aggregate")
            aggregateID = device
            var proc: AudioDeviceIOProcID?
            try check(AudioDeviceCreateIOProcID(aggregateID, tapIOProc,
                                                Unmanaged.passUnretained(ring).toOpaque(), &proc), "create IOProc")
            procID = proc
            try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
        } catch {
            stop()
            throw error
        }
        self.target = target
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID) // waits for an in-flight callback
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        target = nil
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        if status != noErr { throw Failure(step: step, status: status) }
    }

    // MARK: Process lookup

    /// Core Audio process objects that belong to the app `bundleID`: its own processes
    /// (via NSRunningApplication PIDs) plus helpers whose bundle ID extends it
    /// ("com.google.Chrome.helper", "com.spotify.client.helper"…) and the known
    /// out-of-process audio hosts of a few browsers.
    static func processObjects(for bundleID: String) -> [AudioObjectID] {
        var result = Set<AudioObjectID>()
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            if let id = processObject(pid: app.processIdentifier) { result.insert(id) }
        }
        let prefixes = ([bundleID] + (audioHosts[bundleID] ?? [])).map { $0.lowercased() }
        for object in allProcessObjects() {
            guard let bid = string(object, kAudioProcessPropertyBundleID)?.lowercased() else { continue }
            if prefixes.contains(where: { bid == $0 || bid.hasPrefix($0 + ".") }) { result.insert(object) }
        }
        return result.sorted()
    }

    /// Browsers that render audio in a process outside their bundle-ID namespace.
    private static let audioHosts: [String: [String]] = [
        "com.apple.Safari": ["com.apple.WebKit.GPU", "com.apple.WebKit.WebContent"],
        "com.apple.SafariTechnologyPreview": ["com.apple.WebKit.GPU", "com.apple.WebKit.WebContent"],
        "org.mozilla.firefox": ["org.mozilla.plugincontainer"],
        "org.mozilla.firefoxdeveloperedition": ["org.mozilla.plugincontainer"],
    ]

    static func allProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func defaultOutputUID() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return string(device, kAudioDevicePropertyDeviceUID)
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        let s = value.takeRetainedValue() as String
        return s.isEmpty ? nil : s
    }
}

/// Real-time IOProc: copies the tap's Float32 input into the ring. No locks, no
/// allocation, no Objective-C; the ring pointer is unretained (it outlives the IOProc).
private let tapIOProc: AudioDeviceIOProc = { _, _, input, _, _, _, context in
    guard let context else { return noErr }
    let ring = Unmanaged<AudioSampleRing>.fromOpaque(context).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    guard buffers.count > 0 else { return noErr }
    let buffer = buffers[0]
    guard let data = buffer.mData else { return noErr }
    let channels = max(1, Int(buffer.mNumberChannels))
    let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
    ring.write(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels, stride: channels)
    return noErr
}

/// "System Audio Recording" permission (TCC service kTCCServiceAudioCapture). There is no
/// public API to read it, so this uses TCC's preflight/request SPI when present and
/// otherwise reports `.unknown` (starting the tap then shows the system prompt).
enum AudioCapturePermission {
    enum Status { case authorized, denied, unknown }

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
    private static let service = "kTCCServiceAudioCapture" as CFString

    private static let tcc: UnsafeMutableRawPointer? = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    /// Raw TCCAccessPreflight result (0 granted, 1 denied, 2 not determined), -1 = no SPI.
    static var rawPreflight: Int32 {
        guard let tcc, let sym = dlsym(tcc, "TCCAccessPreflight") else { return -1 }
        return unsafeBitCast(sym, to: Preflight.self)(service, nil)
    }

    static var status: Status {
        switch rawPreflight {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Shows the system prompt if the user hasn't decided yet. `nil` = SPI unavailable.
    static func request(_ completion: @escaping @Sendable (Bool?) -> Void) {
        guard let tcc, let sym = dlsym(tcc, "TCCAccessRequest") else { completion(nil); return }
        unsafeBitCast(sym, to: Request.self)(service, nil) { granted in completion(granted) }
    }
}
