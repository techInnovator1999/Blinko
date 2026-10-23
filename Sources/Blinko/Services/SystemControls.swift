import AppKit
import CoreAudio

// MARK: - Output volume (CoreAudio)

@MainActor
enum SystemAudio {
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663) // 'vmvc'

    static func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: virtualMainVolume, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static var canSetVolume: Bool {
        let dev = defaultOutputDevice()
        var addr = volumeAddress
        guard AudioObjectHasProperty(dev, &addr) else { return false }
        var settable: DarwinBoolean = false
        AudioObjectIsPropertySettable(dev, &addr, &settable)
        return settable.boolValue
    }

    static var volume: Float {
        get {
            var v = Float32(0), size = UInt32(MemoryLayout<Float32>.size), addr = volumeAddress
            AudioObjectGetPropertyData(defaultOutputDevice(), &addr, 0, nil, &size, &v)
            return v
        }
        set {
            var v = Float32(min(max(newValue, 0), 1)), addr = volumeAddress
            AudioObjectSetPropertyData(defaultOutputDevice(), &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    static var isMuted: Bool {
        get {
            var m = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size), addr = muteAddress
            AudioObjectGetPropertyData(defaultOutputDevice(), &addr, 0, nil, &size, &m)
            return m != 0
        }
        set {
            var m = UInt32(newValue ? 1 : 0), addr = muteAddress
            AudioObjectSetPropertyData(defaultOutputDevice(), &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
    }
}

/// Mirrors volume changes from any source (keys, Control Center, AirPods) into the HUD.
/// Listeners are removed from the old device before attaching to a new one (no leaks).
@MainActor
final class VolumeObserver {
    private var device = AudioDeviceID(0)
    private var listener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var suppressUntil = Date.distantPast

    func start() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.attach() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block)
        attach()
        // Ignore the burst of callbacks that some devices fire right after attaching.
        suppressUntil = Date().addingTimeInterval(1)
    }

    private func attach() {
        detach()
        device = SystemAudio.defaultOutputDevice()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.changed() }
        }
        listener = block
        var v = SystemAudio.volumeAddress, m = SystemAudio.muteAddress
        AudioObjectAddPropertyListenerBlock(device, &v, .main, block)
        AudioObjectAddPropertyListenerBlock(device, &m, .main, block)
    }

    private func detach() {
        guard let listener, device != 0 else { return }
        var v = SystemAudio.volumeAddress, m = SystemAudio.muteAddress
        AudioObjectRemovePropertyListenerBlock(device, &v, .main, listener)
        AudioObjectRemovePropertyListenerBlock(device, &m, .main, listener)
        self.listener = nil
    }

    private func changed() {
        guard Date() > suppressUntil, Preferences.shared.replaceSystemHUD else { return }
        ActivityCenter.shared.show(.volume(level: SystemAudio.volume, muted: SystemAudio.isMuted))
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
