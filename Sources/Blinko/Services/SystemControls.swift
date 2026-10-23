import AppKit
import CoreAudio

// MARK: - Volume (CoreAudio)

enum AudioDirection {
    case output, input

    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

@MainActor
enum AudioLevels {
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663) // 'vmvc'

    static func defaultDevice(_ dir: AudioDirection) -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: dir.defaultDeviceSelector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func volumeAddress(_ dir: AudioDirection) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: virtualMainVolume, mScope: dir.scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func muteAddress(_ dir: AudioDirection) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: dir.scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func canSetVolume(_ dir: AudioDirection) -> Bool {
        let dev = defaultDevice(dir)
        var addr = volumeAddress(dir)
        guard AudioObjectHasProperty(dev, &addr) else { return false }
        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(dev, &addr, &settable)
        return settable.boolValue
    }

    static func volume(_ dir: AudioDirection) -> Float {
        var v = Float32(0), size = UInt32(MemoryLayout<Float32>.size), addr = volumeAddress(dir)
        AudioObjectGetPropertyData(defaultDevice(dir), &addr, 0, nil, &size, &v)
        return v
    }

    static func setVolume(_ dir: AudioDirection, _ value: Float) {
        var v = Float32(min(max(value, 0), 1)), addr = volumeAddress(dir)
        AudioObjectSetPropertyData(defaultDevice(dir), &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    static func isMuted(_ dir: AudioDirection) -> Bool {
        var m = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size), addr = muteAddress(dir)
        AudioObjectGetPropertyData(defaultDevice(dir), &addr, 0, nil, &size, &m)
        return m != 0
    }

    static func setMuted(_ dir: AudioDirection, _ muted: Bool) {
        var m = UInt32(muted ? 1 : 0), addr = muteAddress(dir)
        AudioObjectSetPropertyData(defaultDevice(dir), &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
    }
}

/// Output-volume convenience used by the media-key handler.
@MainActor
enum SystemAudio {
    static var canSetVolume: Bool { AudioLevels.canSetVolume(.output) }
    static var volume: Float {
        get { AudioLevels.volume(.output) }
        set { AudioLevels.setVolume(.output, newValue) }
    }
    static var isMuted: Bool {
        get { AudioLevels.isMuted(.output) }
        set { AudioLevels.setMuted(.output, newValue) }
    }
}

/// Mirrors volume changes from any source (keys, Control Center, AirPods, Sound settings)
/// into the HUD, for either the output or the microphone. Listeners are removed from the
/// old device before attaching to a new one (no leaks on device switches).
@MainActor
final class VolumeObserver {
    private let direction: AudioDirection
    private var device = AudioDeviceID(0)
    private var listener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var suppressUntil = Date.distantPast

    init(direction: AudioDirection) { self.direction = direction }

    func start() {
        var addr = AudioObjectPropertyAddress(mSelector: direction.defaultDeviceSelector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.attach() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        attach()
    }

    private func attach() {
        detach()
        device = AudioLevels.defaultDevice(direction)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
        listener = block
        var v = AudioLevels.volumeAddress(direction), m = AudioLevels.muteAddress(direction)
        AudioObjectAddPropertyListenerBlock(device, &v, .main, block)
        AudioObjectAddPropertyListenerBlock(device, &m, .main, block)
        // Ignore the burst of callbacks some devices fire right after attaching.
        suppressUntil = Date().addingTimeInterval(1)
    }

    private func detach() {
        guard let listener, device != 0 else { return }
        var v = AudioLevels.volumeAddress(direction), m = AudioLevels.muteAddress(direction)
        AudioObjectRemovePropertyListenerBlock(device, &v, .main, listener)
        AudioObjectRemovePropertyListenerBlock(device, &m, .main, listener)
        self.listener = nil
    }

    private func changed() {
        guard Date() > suppressUntil else { return }
        let level = AudioLevels.volume(direction), muted = AudioLevels.isMuted(direction)
        switch direction {
        case .output:
            guard Preferences.shared.replaceSystemHUD else { return }
            ActivityCenter.shared.show(.volume(level: level, muted: muted))
        case .input:
            guard Preferences.shared.micHUD else { return }
            ActivityCenter.shared.show(.microphone(level: level, muted: muted))
        }
    }
}

// MARK: - Display brightness (DisplayServices, private)

@MainActor
enum DisplayBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
        .map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
        .map { unsafeBitCast($0, to: SetFn.self) }

    static var display: CGDirectDisplayID {
        NSScreen.screens.first(where: \.isBuiltIn)?.displayID ?? CGMainDisplayID()
    }

    static var isAvailable: Bool { getFn != nil && setFn != nil && get() != nil }

    static func get() -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) {
        _ = setFn?(display, min(max(value, 0), 1))
    }
}

// MARK: - Keyboard backlight (CoreBrightness, private)

@MainActor
enum KeyboardBacklight {
    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private static let client: NSObject? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    private static let keyboardID: UInt64? = {
        guard let client,
              client.responds(to: NSSelectorFromString("copyKeyboardBacklightIDs")),
              let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?
                  .takeRetainedValue() as? [NSNumber]
        else { return nil }
        return ids.first?.uint64Value
    }()

    static var isAvailable: Bool { keyboardID != nil }

    static func get() -> Float? {
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard let client, let id = keyboardID, client.responds(to: sel) else { return nil }
        let fn = unsafeBitCast(client.method(for: sel), to: GetFn.self)
        return fn(client, sel, id)
    }

    static func set(_ value: Float) {
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let client, let id = keyboardID, client.responds(to: sel) else { return }
        let fn = unsafeBitCast(client.method(for: sel), to: SetFn.self)
        _ = fn(client, sel, min(max(value, 0), 1), id)
    }
}
