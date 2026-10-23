import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Blinko: launch at login failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Global hotkey via Carbon (no Accessibility permission needed). Default: ⌃⌥Space.
@MainActor
final class HotkeyManager {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x424C_4E4B), id: 1) // 'BLNK'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}

/// Optional menu bar icon for discoverability (the app has no Dock icon).
@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private weak var manager: NotchManager?

    init(manager: NotchManager) {
        self.manager = manager
        super.init()
        sync()
        observe()
    }

    private func observe() {
        withObservationTracking { _ = Preferences.shared.showMenuBarIcon } onChange: { [weak self] in
            DispatchQueue.main.async { self?.sync(); self?.observe() }
        }
    }

    private func sync() {
        if Preferences.shared.showMenuBarIcon {
            guard item == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = BrandMark.menuBarImage()
            item.button?.image?.accessibilityDescription = "Blinko"
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Island", action: #selector(openIsland), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Open Shelf", action: #selector(openShelf), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Blinko", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            item.menu = menu
            self.item = item
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    @objc private func openIsland() { manager?.toggleOnActiveScreen() }
    @objc private func openShelf() { manager?.open(tab: .shelf) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
}
