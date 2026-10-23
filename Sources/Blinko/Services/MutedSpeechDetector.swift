import Accelerate
import AVFoundation
import CoreAudio
import Foundation

/// "You're muted" detection. Runs only while in a call, muted in the meeting app, with the
/// warning on and microphone access granted (see `MeetingService.updateDetector`).
///
/// Two signals, best first:
/// 1. CoreAudio voice activity detection (`kAudioDevicePropertyVoiceActivityDetectionEnable`,
///    macOS 14+): echo-cancelled, so other participants coming out of the speakers don't count.
///    Event-driven (a property listener). Apple documents that it works with a *process* mute
///    but not with a hardware mute.
/// 2. Fallback: RMS level of the input tap (~11 callbacks/s, vDSP), speech = sustained energy
///    above a noise floor. Can be fooled by loud speaker bleed; mitigated by the 0.6 s window.
///
/// Either way, a hardware/system input mute (what Blinko's Mute button sets) zeroes the input
/// for every process, so speech can't be heard then — the warning is for app-level mutes.
@MainActor
final class MutedSpeechDetector {
    static let shared = MutedSpeechDetector()

    var onSpeech: (() -> Void)?
    private(set) var isRunning = false

    private var engine: AVAudioEngine?
    private var vadDevice = AudioObjectID(kAudioObjectUnknown)
    private var vadListener: AudioObjectPropertyListenerBlock?
    private var vadSustain: DispatchWorkItem?
    private let meter = SpeechMeter()

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var isDenied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        return s == .denied || s == .restricted
    }

    static func requestAccess(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(granted) } }
        }
    }

    func start() {
        guard !isRunning, Self.isAuthorized else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        let usesVAD = enableVAD()
        meter.reset(levelDetection: !usesVAD)
        let meter = self.meter
        // ~85 ms buffers: plenty for a 0.6 s decision, ~12 wakeups/s only in this narrow case.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if meter.process(buffer) {
                DispatchQueue.main.async { MainActor.assumeIsolated { MutedSpeechDetector.shared.onSpeech?() } }
            }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            disableVAD()
            return
        }
        self.engine = engine
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        disableVAD()
    }

    // MARK: Voice activity detection

    private func enableVAD() -> Bool {
        let device = AudioLevels.defaultDevice(.input)
        var enable = Self.address(kAudioDevicePropertyVoiceActivityDetectionEnable)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &enable) else { return false }
        var on: UInt32 = 1
        guard AudioObjectSetPropertyData(device, &enable, 0, nil, UInt32(MemoryLayout<UInt32>.size), &on) == noErr
        else { return false }
        var state = Self.address(kAudioDevicePropertyVoiceActivityDetectionState)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.vadChanged() }
        }
        guard AudioObjectAddPropertyListenerBlock(device, &state, .main, block) == noErr else {
            var off: UInt32 = 0
            AudioObjectSetPropertyData(device, &enable, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
            return false
        }
        vadDevice = device
        vadListener = block
        return true
    }

    private func disableVAD() {
        vadSustain?.cancel()
        vadSustain = nil
        guard vadDevice != kAudioObjectUnknown else { return }
        if let block = vadListener {
            var state = Self.address(kAudioDevicePropertyVoiceActivityDetectionState)
            AudioObjectRemovePropertyListenerBlock(vadDevice, &state, .main, block)
        }
        var enable = Self.address(kAudioDevicePropertyVoiceActivityDetectionEnable)
        var off: UInt32 = 0
        AudioObjectSetPropertyData(vadDevice, &enable, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
        vadListener = nil
        vadDevice = AudioObjectID(kAudioObjectUnknown)
    }

    /// Voice must last 0.6 s: a cough or a "hm" doesn't trigger the warning.
    private func vadChanged() {
        var state = Self.address(kAudioDevicePropertyVoiceActivityDetectionState)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(vadDevice, &state, 0, nil, &size, &value)
        if value != 0 {
            guard vadSustain == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.vadSustain = nil
                self?.onSpeech?()
            }
            vadSustain = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        } else {
            vadSustain?.cancel()
            vadSustain = nil
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}

/// Level-based speech detector fed from the audio tap thread. Callbacks are serial, so the
/// state needs no lock; `reset` happens before the tap is installed.
final class SpeechMeter: @unchecked Sendable {
    /// dBFS above which a buffer counts as voice (also at least 12 dB over the noise floor).
    static let threshold: Float = -42
    static let sustain: Double = 0.6
    /// A gap this long ends the utterance.
    static let gap: Double = 0.25

    private var levelDetection = true
    private var floor: Float = -60
    private var voiced: Double = 0
    private var silent: Double = 0
    private var fired = false

    func reset(levelDetection: Bool) {
        self.levelDetection = levelDetection
        floor = -60
        voiced = 0
        silent = 0
        fired = false
    }

    /// Returns true once per utterance when voice has lasted `sustain` seconds.
    func process(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard levelDetection, let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return false }
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(buffer.frameLength))
        let duration = Double(buffer.frameLength) / max(buffer.format.sampleRate, 1)
        return feed(db: 20 * log10(max(rms, 1e-7)), duration: duration)
    }

    /// Pure decision logic (unit-tested by `--selftest`).
    func feed(db: Float, duration: Double) -> Bool {
        let isVoice = db > max(Self.threshold, floor + 12)
        if isVoice {
            voiced += duration
            silent = 0
        } else {
            // The noise floor follows quiet input quickly and loud input slowly.
            floor = db < floor ? db : floor + (db - floor) * 0.02
            silent += duration
            if silent >= Self.gap { voiced = 0; fired = false }
        }
        if voiced >= Self.sustain, !fired {
            fired = true
            return true
        }
        return false
    }
}
