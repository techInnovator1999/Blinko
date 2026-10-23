import CoreAudio
import CoreMediaIO
import Foundation
import Observation

/// Camera / microphone "in use" indicators, entirely listener-driven:
/// - camera: CoreMediaIO `DeviceIsRunningSomewhere` on every video device (+ device list changes);
/// - microphone: CoreAudio `DeviceIsRunningSomewhere` on the default input device, re-attached
///   when the default input changes (old listener removed first).
/// Screen recording has no public "in use" signal, so it is not shown.
@MainActor
@Observable
final class PrivacyService {
    static let shared = PrivacyService()

    private(set) var cameraInUse = false
    private(set) var micInUse = false
    var anyInUse: Bool { cameraInUse || micInUse }

    @ObservationIgnored private var running = false
    @ObservationIgnored private var cameraListeners: [(CMIOObjectID, CMIOObjectPropertyListenerBlock)] = []
    @ObservationIgnored private var cameraListListener: CMIOObjectPropertyListenerBlock?
    @ObservationIgnored private var micDevice = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var micListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var defaultInputListener: AudioObjectPropertyListenerBlock?

    func refresh() {
        // Meeting mode reads camera / microphone state too (its card and fallback detection).
        Preferences.shared.privacyIndicators || Preferences.shared.meetingMode ? start() : stop()
    }

    private func start() {
        guard !running else { return }
        running = true
        attachCameras()
        var list = Self.cmioAddress(kCMIOHardwarePropertyDevices)
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachCameras() }
        }
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &list, .main, block) == noErr {
            cameraListListener = block
        }

        attachMicrophone()
        var def = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
        let defBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachMicrophone() }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &def, .main, defBlock) == noErr {
            defaultInputListener = defBlock
        }
    }

    private func stop() {
        guard running else { return }
        running = false
        detachCameras()
        if let block = cameraListListener {
            var list = Self.cmioAddress(kCMIOHardwarePropertyDevices)
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &list, .main, block)
            cameraListListener = nil
        }
        detachMicrophone()
        if let block = defaultInputListener {
            var def = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &def, .main, block)
            defaultInputListener = nil
        }
        cameraInUse = false
        micInUse = false
    }

    // MARK: Camera (CoreMediaIO)

    private func attachCameras() {
        detachCameras()
        var addr = Self.cmioAddress(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return updateCamera() }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == noErr else { return updateCamera() }

        for device in devices {
            var running = Self.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updateCamera() }
            }
            if CMIOObjectAddPropertyListenerBlock(device, &running, .main, block) == noErr {
                cameraListeners.append((device, block))
            }
        }
        updateCamera()
    }

    private func detachCameras() {
        for (device, block) in cameraListeners {
            var running = Self.cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectRemovePropertyListenerBlock(device, &running, .main, block)
        }
        cameraListeners.removeAll()
    }

    private func updateCamera() {
        let active = cameraListeners.contains { Self.cmioIsRunning($0.0) }
            && !CameraService.shared.isMirrorRunning // our own mirror doesn't count
        guard active != cameraInUse else { return }
        cameraInUse = active
        if active, Preferences.shared.privacyIndicators { ActivityCenter.shared.show(.privacy(sensor: .camera)) }
    }

    private static func cmioIsRunning(_ device: CMIOObjectID) -> Bool {
        var addr = cmioAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return status == noErr && value != 0
    }

    private static func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    // MARK: Microphone (CoreAudio)

    private func attachMicrophone() {
        detachMicrophone()
        var addr = Self.audioAddress(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return updateMicrophone() }

        var running = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateMicrophone() }
        }
        if AudioObjectAddPropertyListenerBlock(device, &running, .main, block) == noErr {
            micDevice = device
            micListener = block
        }
        updateMicrophone()
    }

    private func detachMicrophone() {
        if let block = micListener, micDevice != kAudioObjectUnknown {
            var running = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(micDevice, &running, .main, block)
        }
        micListener = nil
        micDevice = AudioObjectID(kAudioObjectUnknown)
    }

    private func updateMicrophone() {
        var active = false
        if micDevice != kAudioObjectUnknown {
            var addr = Self.audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            active = AudioObjectGetPropertyData(micDevice, &addr, 0, nil, &size, &value) == noErr && value != 0
        }
        guard active != micInUse else { return }
        micInUse = active
        if active, Preferences.shared.privacyIndicators { ActivityCenter.shared.show(.privacy(sensor: .microphone)) }
    }

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Design-time state for snapshot rendering.
    func injectPreview(camera: Bool, mic: Bool) {
        cameraInUse = camera
        micInUse = mic
    }
}
