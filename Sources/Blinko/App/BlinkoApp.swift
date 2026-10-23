import AppKit

@main
enum BlinkoMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if Snapshot.runIfRequested() { return }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchManager: NotchManager?
    private var statusItem: StatusItemController?
    private let hotkey = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.shared

        ServiceHub.shared.start()

        let manager = NotchManager()
        manager.start()
        notchManager = manager

        statusItem = StatusItemController(manager: manager)

        hotkey.onPress = { [weak manager] in manager?.toggleOnActiveScreen() }
        hotkey.register()

        if !prefs.hasCompletedOnboarding {
            SettingsWindowController.shared.show(pane: .welcome)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }
}
