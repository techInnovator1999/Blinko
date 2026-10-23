import AppKit

@main
enum BlinkoMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        if Snapshot.runIfRequested() { return }
        if SelfTest.runIfRequested() { return }
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
    private let commandHotkey = HotkeyManager(id: 2)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Preferences.shared

        Motion.startObservingReducedMotion()
        Theme.shared.start() // samples the wallpaper only while "Match wallpaper" is the accent
        ServiceHub.shared.start()
        _ = UpdateService.shared // starts Sparkle's scheduled checks

        let manager = NotchManager()
        manager.start()
        notchManager = manager
        AppRouter.shared.attach(manager)

        statusItem = StatusItemController(manager: manager)

        hotkey.onPress = { [weak manager] in manager?.toggleOnActiveScreen() }
        syncHotkey()
        commandHotkey.onPress = { [weak manager] in manager?.toggleCommandBar() }
        syncCommandHotkey()

        if !prefs.hasCompletedOnboarding {
            SettingsWindowController.shared.show(pane: .welcome)
        }
    }

    /// Re-registers the global shortcut whenever it is edited in Settings.
    private func syncHotkey() {
        let prefs = Preferences.shared
        withObservationTracking {
            if prefs.hotkeyEnabled, !HotkeyRecorderState.isRecording {
                hotkey.register(keyCode: UInt32(prefs.hotkeyKeyCode), modifiers: UInt32(prefs.hotkeyModifiers))
            } else {
                hotkey.unregister()
            }
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.syncHotkey() }
        }
    }

    /// The command bar's shortcut (⌥Space by default), registered beside the island toggle.
    private func syncCommandHotkey() {
        let prefs = Preferences.shared
        withObservationTracking {
            if prefs.commandBarEnabled, !HotkeyRecorderState.isRecording {
                commandHotkey.register(keyCode: UInt32(prefs.commandHotkeyKeyCode),
                                       modifiers: UInt32(prefs.commandHotkeyModifiers))
            } else {
                commandHotkey.unregister()
            }
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.syncCommandHotkey() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeepAwakeService.shared.stop()
        NotesService.shared.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }
}
