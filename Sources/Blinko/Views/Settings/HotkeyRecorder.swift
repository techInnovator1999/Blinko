import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Shared flag so the live hotkey is suspended while a new one is being recorded.
@MainActor
@Observable
final class HotkeyRecorderState {
    static let shared = HotkeyRecorderState()
    var recording = false
    static var isRecording: Bool { shared.recording }
}

enum HotkeyFormat {
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return m
    }

    static func symbols(for carbon: Int) -> String {
        var s = ""
        if carbon & controlKey != 0 { s += "⌃" }
        if carbon & optionKey != 0 { s += "⌥" }
        if carbon & shiftKey != 0 { s += "⇧" }
        if carbon & cmdKey != 0 { s += "⌘" }
        return s
    }

    static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            if let fn = functionKeys[Int(event.keyCode)] { return fn }
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// Click, then press a key combination (must include ⌘, ⌃ or ⌥). Esc cancels.
struct HotkeyRecorder: View {
    @State private var monitor: Any?
    @State private var invalid = false
    private var recorder = HotkeyRecorderState.shared

    var body: some View {
        let prefs = Preferences.shared
        let recording = recorder.recording
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type shortcut…" : HotkeyFormat.symbols(for: prefs.hotkeyModifiers) + prefs.hotkeyKeyName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(recording ? Color.accentColor : .primary)
                .frame(minWidth: 110)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(recording ? Color.accentColor : (invalid ? .red : Color.secondary.opacity(0.4)), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recorder.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let mods = HotkeyFormat.carbonModifiers(from: event.modifierFlags)
            guard mods & (cmdKey | controlKey | optionKey) != 0 else {
                invalid = true
                NSSound.beep()
                return nil
            }
            let prefs = Preferences.shared
            prefs.hotkeyKeyCode = Int(event.keyCode)
            prefs.hotkeyModifiers = mods
            prefs.hotkeyKeyName = HotkeyFormat.keyName(for: event)
            invalid = false
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recorder.recording = false
    }
}
