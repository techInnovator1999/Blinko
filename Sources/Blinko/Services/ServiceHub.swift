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
        observeMeetingPreferences()
    }

    private func applyPreferences() {
        MediaKeyService.shared.refresh()
        ClipboardService.shared.refresh()
        FocusService.shared.refresh()
        PrivacyService.shared.refresh()
        NetworkService.shared.refresh()
        DownloadsService.shared.refresh()
        WeatherService.shared.refresh()
        MeetingService.shared.refresh()
    }

    private func observePreferences() {
        let prefs = Preferences.shared
        withObservationTracking {
            _ = prefs.replaceSystemHUD
            _ = prefs.capsLockHUD
            _ = prefs.clipboardHistory
            _ = prefs.focusActivity
            _ = prefs.privacyIndicators
            _ = prefs.networkActivity
            _ = prefs.downloadsActivity
            _ = prefs.weatherEnabled
            _ = prefs.meetingMode
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.applyPreferences()
                self?.observePreferences()
            }
        }
    }

    /// Meeting sub-settings re-evaluate the call; they don't restart every service.
    private func observeMeetingPreferences() {
        withObservationTracking {
            _ = Preferences.shared.mutedWarning
            _ = Preferences.shared.disabledMeetingApps
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MeetingService.shared.preferencesChanged()
                self?.observeMeetingPreferences()
            }
        }
    }
}
