import Foundation

/// Starts services and keeps them in sync with preferences. Features that are turned
/// off do no background work at all.
@MainActor
final class ServiceHub {
    static let shared = ServiceHub()

    private let volumeObserver = VolumeObserver(direction: .output)
    private let micObserver = VolumeObserver(direction: .input)

    func start() {
        BatteryService.shared.start()
        BluetoothService.shared.start()
        volumeObserver.start()
        micObserver.start()
        // Defer non-critical startup work so the island appears instantly.
        DispatchQueue.main.async {
            NowPlayingService.shared.start()
            CalendarService.shared.start()
        }
        applyPreferences()
        observePreferences()
    }

    private func applyPreferences() {
        MediaKeyService.shared.refresh()
        ClipboardService.shared.refresh()
    }

    private func observePreferences() {
        let prefs = Preferences.shared
        withObservationTracking {
            _ = prefs.replaceSystemHUD
            _ = prefs.capsLockHUD
            _ = prefs.clipboardHistory
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applyPreferences()
                self?.observePreferences()
            }
        }
    }
}
