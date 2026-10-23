import Foundation
import IOKit.ps
import Observation

/// Power state via IOKit power-source notifications. Zero polling: the kernel calls us.
@MainActor
@Observable
final class BatteryService {
    static let shared = BatteryService()

    private(set) var hasBattery = false
    private(set) var level = 100
    private(set) var isCharging = false
    private(set) var isPluggedIn = false
    private(set) var minutesRemaining: Int?
    private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var lowWarned: Set<Int> = []
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        read(notify: false)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.read(notify: true) }
        }, ctx)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }

        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    private func read(notify: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let ps = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any]
        else { hasBattery = false; return }

        let wasPlugged = isPluggedIn
        hasBattery = (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
        let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
        let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let minutes = (charging ? desc[kIOPSTimeToFullChargeKey] : desc[kIOPSTimeToEmptyKey]) as? Int

        if level != newLevel { level = newLevel }
        if isCharging != charging { isCharging = charging }
        if isPluggedIn != plugged { isPluggedIn = plugged }
        let remaining = (minutes ?? -1) > 0 ? minutes : nil
        if minutesRemaining != remaining { minutesRemaining = remaining }

        guard notify, hasBattery, Preferences.shared.batteryActivity else { return }
        if plugged != wasPlugged {
            ActivityCenter.shared.show(.power(level: newLevel, charging: charging, pluggedIn: plugged))
            lowWarned.removeAll()
        } else if !plugged {
            for threshold in [20, 10, 5] where newLevel <= threshold && !lowWarned.contains(threshold) {
                lowWarned.insert(threshold)
                ActivityCenter.shared.show(.lowBattery(level: newLevel))
                break
            }
        }
    }
}
