import Foundation
import IOBluetooth

/// Connect / disconnect live activities via IOBluetooth notifications (no scanning).
@MainActor
final class BluetoothService: NSObject {
    static let shared = BluetoothService()

    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [IOBluetoothUserNotification] = []
    private var startedAt = Date()

    func start() {
        guard connectNote == nil else { return }
        startedAt = Date()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let n = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))) {
            disconnectNotes.append(n)
        }
        // IOBluetooth replays already-connected devices at registration; skip that burst.
        guard Date().timeIntervalSince(startedAt) > 3, Preferences.shared.bluetoothActivity else { return }
        let name = device.nameOrAddress ?? "Device"
        let kind = kind(of: device)
        let battery = kind == .headphones ? Self.battery(of: device) : nil
        ActivityCenter.shared.show(.bluetooth(name: name, kind: kind, connected: true, battery: battery))

        // Levels usually arrive a moment after the link comes up: look once more, and morph
        // the activity in place if it is still showing this device.
        guard kind == .headphones, battery == nil, Preferences.shared.airPodsBattery else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let battery = Self.battery(of: device),
                  case .bluetooth(name, kind, true, _)? = ActivityCenter.shared.current else { return }
            ActivityCenter.shared.show(.bluetooth(name: name, kind: kind, connected: true, battery: battery))
        }
    }

    /// AirPods / Beats battery via private IOBluetoothDevice properties. Best-effort: each
    /// key is checked with `responds(to:)` first, so a missing property can never throw.
    private static func battery(of device: IOBluetoothDevice) -> DeviceBattery? {
        guard Preferences.shared.airPodsBattery else { return nil }
        func level(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let value = (device.value(forKey: key) as? NSNumber)?.intValue,
                  (1...100).contains(value) else { return nil }
            return value
        }
        let battery = DeviceBattery(left: level("batteryPercentLeft"), right: level("batteryPercentRight"),
                                    caseLevel: level("batteryPercentCase"), single: level("batteryPercentSingle"))
        return battery.isEmpty ? nil : battery
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        disconnectNotes.removeAll { $0 === note }
        guard Preferences.shared.bluetoothActivity else { return }
        ActivityCenter.shared.show(.bluetooth(name: device.nameOrAddress ?? "Device", kind: kind(of: device), connected: false))
    }

    private func kind(of device: IOBluetoothDevice) -> BluetoothDeviceKind {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods") || name.contains("beats") || name.contains("buds") || name.contains("headphone") { return .headphones }
        if name.contains("keyboard") { return .keyboard }
        if name.contains("trackpad") { return .trackpad }
        if name.contains("mouse") { return .mouse }
        // Major device class: 0x04 audio/video, 0x05 peripheral.
        switch device.deviceClassMajor {
        case 0x04: return name.contains("speaker") ? .speaker : .headphones
        case 0x05:
            let minor = device.deviceClassMinor
            if minor & 0x10 != 0 { return .keyboard }
            if minor & 0x20 != 0 { return .mouse }
            return .generic
        default: return .generic
        }
    }
}
