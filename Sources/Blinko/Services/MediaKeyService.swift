import AppKit
import ApplicationServices

/// Intercepts volume / brightness / keyboard-backlight keys, applies the change itself
/// and swallows the event so the system OSD never appears. Requires Accessibility.
///
/// The tap is only installed while "Replace system HUD" is on, re-enables itself when
/// macOS disables it for timeout, and the callback does constant-time work.
@MainActor
final class MediaKeyService {
    static let shared = MediaKeyService()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionPoll: Timer?
    private var lastAuxBrightness = Date.distantPast
    private var capsLockOn = false

    private enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
        case illuminationUp = 21, illuminationDown = 22
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        waitForPermission()
    }

    func refresh() {
        let prefs = Preferences.shared
        if prefs.replaceSystemHUD || prefs.capsLockHUD { install() } else { uninstall() }
    }

    private func install() {
        guard tap == nil else { return }
        guard isTrusted else { waitForPermission(); return }

        let mask = (CGEventMask(1) << 14) // NX_SYSDEFINED (media keys)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        capsLockOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MediaKeyService>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated { me.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Slow, short-lived poll only while waiting for the user to grant Accessibility.
    private func waitForPermission() {
        guard permissionPoll == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.isTrusted else { return }
                t.invalidate()
                self.permissionPoll = nil
                self.refresh()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        permissionPoll = timer
    }

    // MARK: Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Caps Lock: observe only, never swallow.
        if type == .flagsChanged {
            let on = event.flags.contains(.maskAlphaShift)
            if on != capsLockOn {
                capsLockOn = on
                if Preferences.shared.capsLockHUD { ActivityCenter.shared.show(.capsLock(on: on)) }
            }
            return Unmanaged.passUnretained(event)
        }

        guard Preferences.shared.replaceSystemHUD else { return Unmanaged.passUnretained(event) }

        // Apple Silicon built-in keyboards may send brightness as plain key codes.
        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard code == 144 || code == 145,
                  Date().timeIntervalSince(lastAuxBrightness) > 0.2,
                  DisplayBrightness.isAvailable else { return Unmanaged.passUnretained(event) }
            adjustBrightness(up: code == 144, fine: isFine(event.flags))
            return nil
        }

        guard type.rawValue == 14,
              let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = ns.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let isDown = ((data & 0xFF00) >> 8) == 0xA
        guard let key = Key(rawValue: keyCode) else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        // Option alone keeps the system behaviour (opens the related Settings pane).
        if flags.contains(.maskAlternate), !flags.contains(.maskShift) { return Unmanaged.passUnretained(event) }

        switch key {
        case .soundUp, .soundDown, .mute:
            guard SystemAudio.canSetVolume else { return Unmanaged.passUnretained(event) }
            if isDown { adjustVolume(key, fine: isFine(flags)) }
        case .brightnessUp, .brightnessDown:
            guard DisplayBrightness.isAvailable else { return Unmanaged.passUnretained(event) }
            lastAuxBrightness = Date()
            if isDown { adjustBrightness(up: key == .brightnessUp, fine: isFine(flags)) }
        case .illuminationUp, .illuminationDown:
            guard KeyboardBacklight.isAvailable else { return Unmanaged.passUnretained(event) }
            if isDown { adjustBacklight(up: key == .illuminationUp, fine: isFine(flags)) }
        }
        return nil
    }

    private func isFine(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate) && flags.contains(.maskShift)
    }

    private func step(_ value: Float, up: Bool, fine: Bool) -> Float {
        let unit: Float = fine ? 1 / 64 : 1 / 16
        let snapped = (value / unit).rounded() * unit
        return min(max(snapped + (up ? unit : -unit), 0), 1)
    }

    private func adjustVolume(_ key: Key, fine: Bool) {
        if key == .mute {
            SystemAudio.isMuted.toggle()
        } else {
            let next = step(SystemAudio.volume, up: key == .soundUp, fine: fine)
            SystemAudio.volume = next
            if SystemAudio.isMuted, key == .soundUp { SystemAudio.isMuted = false }
        }
        // Show immediately; the CoreAudio listener will confirm with the same value.
        ActivityCenter.shared.show(.volume(level: SystemAudio.volume, muted: SystemAudio.isMuted))
    }

    private func adjustBrightness(up: Bool, fine: Bool) {
        guard let current = DisplayBrightness.get() else { return }
        let next = step(current, up: up, fine: fine)
        DisplayBrightness.set(next)
        ActivityCenter.shared.show(.brightness(level: next))
    }

    private func adjustBacklight(up: Bool, fine: Bool) {
        guard let current = KeyboardBacklight.get() else { return }
        let next = step(current, up: up, fine: fine)
        KeyboardBacklight.set(next)
        ActivityCenter.shared.show(.keyboardBacklight(level: next))
    }
}
