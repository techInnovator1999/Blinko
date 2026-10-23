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
        ActivityCenter.shared.show(.bluetooth(name: device.nameOrAddress ?? "Device", kind: kind(of: device), connected: true))
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
