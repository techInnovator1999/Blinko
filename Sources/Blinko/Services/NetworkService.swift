import CoreLocation
import CoreWLAN
import Foundation
import Network

/// Wi-Fi / VPN / Personal Hotspot alerts from `NWPathMonitor` (event-driven, its own queue).
/// Changes are debounced so a quick drop-and-reconnect doesn't flash two activities.
/// The network name is read via CoreWLAN only when Location is already authorized
/// (macOS hides SSIDs otherwise); Blinko never asks for Location just for this.
@MainActor
final class NetworkService {
    static let shared = NetworkService()

    private struct State: Equatable {
        var online = false
        var wifi = false
        var expensive = false
        var vpn = false
    }

    private var monitor: NWPathMonitor?
    private var last: State?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "app.blinko.network", qos: .utility)

    func refresh() {
        Preferences.shared.networkActivity ? start() : stop()
    }

    private func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let state = Self.state(of: path)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(state) } }
        }
        m.start(queue: queue)
        monitor = m
    }

    private func stop() {
        monitor?.cancel()
        monitor = nil
        pending?.cancel()
        last = nil
    }

    private nonisolated static func state(of path: NWPath) -> State {
        let tunnels = ["utun", "ipsec", "ppp", "tun", "tap", "wg"]
        let vpn = path.availableInterfaces.contains { iface in
            iface.type == .other && tunnels.contains { iface.name.hasPrefix($0) }
        }
        let online = path.status == .satisfied
        return State(online: online, wifi: online && path.usesInterfaceType(.wifi),
                     expensive: path.isExpensive, vpn: online && vpn)
    }

    private func received(_ state: State) {
        // The first update is the current state, not a change.
        guard let previous = last else { last = state; return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit(state, previous: previous) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func commit(_ state: State, previous: State) {
        last = state
        guard state != previous, Preferences.shared.networkActivity else { return }
        let event: NetworkEvent
        if state.wifi != previous.wifi {
            if state.wifi {
                let ssid = Self.currentSSID()
                event = state.expensive ? .hotspot(name: ssid) : .wifi(connected: true, ssid: ssid)
            } else {
                event = .wifi(connected: false, ssid: nil)
            }
        } else if state.vpn != previous.vpn {
            event = .vpn(on: state.vpn)
        } else if state.wifi, state.expensive != previous.expensive, state.expensive {
            event = .hotspot(name: Self.currentSSID())
        } else {
            return
        }
        ActivityCenter.shared.show(.network(event))
    }

    private static func currentSSID() -> String? {
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedAlways || status == .authorized else { return nil }
        return CWWiFiClient.shared().interface()?.ssid()
    }
}
