import AppKit
import SwiftUI

/// Settings → Meetings: Meeting mode, the "You're muted" warning, which apps count.
struct MeetingsPane: View {
    @State private var micAuthorized = MutedSpeechDetector.isAuthorized
    @State private var micDenied = MutedSpeechDetector.isDenied
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                Toggle("Meeting mode", isOn: $p.meetingMode)
            } footer: {
                Text("When an app below starts using the microphone, the closed island shows the call's app, its length and your microphone, and Home shows mute, camera and leave controls with the calendar event happening now. Detection asks for no permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Warn when I talk while muted", isOn: mutedWarning)
                    .disabled(!p.meetingMode)
                if p.mutedWarning, micDenied {
                    HStack {
                        Label("Microphone access denied", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                    }
                }
                if p.mutedWarning, !trusted {
                    HStack {
                        Label("Accessibility lets Blinko see Zoom's mute and leave calls", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant…") { MediaKeyService.shared.requestPermission() }
                    }
                    .font(.callout)
                }
            } header: {
                Text("You're muted")
            } footer: {
                Text("Blinko listens only while you are in a call and muted in the meeting app, and never records. It can't hear you when the microphone itself is muted (Blinko's Mute button mutes it for every app), so the warning covers mutes made inside the meeting app: Zoom (read from its menu, needs Accessibility), and apps that release the microphone while muted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(MeetingApp.catalog) { app in
                    Toggle(isOn: appEnabled(app)) {
                        HStack(spacing: 8) {
                            AppIconImage(bundleID: app.bundleIDs[0], symbol: app.symbol)
                            Text(verbatim: app.name)
                        }
                    }
                }
            } header: {
                Text("Apps that count as a call")
            } footer: {
                Text("Browsers count when a page uses the microphone (Google Meet, Teams or Zoom on the web); the calendar event happening now names the call. Leave uses Teams' and Slack's own shortcuts, and Zoom's (which asks to confirm), when Accessibility is granted; otherwise it brings the call to the front.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!p.meetingMode)
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            trusted = AXIsProcessTrusted()
            micAuthorized = MutedSpeechDetector.isAuthorized
            micDenied = MutedSpeechDetector.isDenied
        }
    }

    /// Turning the warning on asks for microphone access (only then, never at launch).
    private var mutedWarning: Binding<Bool> {
        Binding(get: { Preferences.shared.mutedWarning }, set: { on in
            Preferences.shared.mutedWarning = on
            guard on, !MutedSpeechDetector.isAuthorized, !MutedSpeechDetector.isDenied else { return }
            MutedSpeechDetector.requestAccess { granted in
                micAuthorized = granted
                micDenied = !granted
                MeetingService.shared.preferencesChanged()
            }
        })
    }

    private func appEnabled(_ app: MeetingApp) -> Binding<Bool> {
        Binding(get: { !Preferences.shared.disabledMeetingApps.contains(app.id) }, set: { on in
            if on { Preferences.shared.disabledMeetingApps.remove(app.id) } else { Preferences.shared.disabledMeetingApps.insert(app.id) }
        })
    }
}

/// Small app icon for settings rows; an SF Symbol when the app isn't installed.
private struct AppIconImage: View {
    let bundleID: String
    let symbol: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: symbol).frame(width: 18, height: 18).foregroundStyle(.secondary)
        }
    }
}

/// Settings → Command Bar: second global shortcut and what it can do.
struct CommandBarPane: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                Toggle("Command bar", isOn: $p.commandBarEnabled)
                if p.commandBarEnabled {
                    LabeledContent("Shortcut") { HotkeyRecorder(.commandBar) }
                }
            } footer: {
                Text("Opens the island as a command bar from any app. ↑ ↓ choose, ↩ runs, ⌘↩ shows files and apps in Finder, ⎋ or a click elsewhere closes it and returns to the app you were in.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("What you can type") {
                ExampleRow(symbol: "equal", tint: .orange, title: "Calculator", example: "(12 + 4) * 3^2 / 5 · sqrt(2) · 15% · 10 % 3")
                ExampleRow(symbol: "arrow.left.arrow.right", tint: .teal, title: "Units", example: "10 km to mi · 72f in c · 5 lb to kg")
                ExampleRow(symbol: "dollarsign.arrow.circlepath", tint: .green, title: "Currency", example: "100 usd to eur · €50 in £")
                ExampleRow(symbol: "app.fill", tint: .blue, title: "Apps & Shortcuts", example: "safari · vsc · any Shortcut by name")
                ExampleRow(symbol: "tray.full.fill", tint: .cyan, title: "Shelf & clipboard", example: "part of a file name or copied text")
                ExampleRow(symbol: "timer", tint: .orange, title: "Blinko", example: "t 5m · timer 1h30 · focus · awake 2h · open shelf")
                ExampleRow(symbol: "magnifyingglass", tint: .blue, title: "Web", example: "anything else searches the web")
            }
            Section {
                EmptyView()
            } footer: {
                Text("Exchange rates come from open.er-api.com, fetched at most once a day and only when you type a currency. Apps and Shortcuts are listed the first time you open the bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ExampleRow: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let example: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(tint.gradient))
            Text(title)
            Spacer()
            Text(verbatim: example).foregroundStyle(.secondary).font(.callout).lineLimit(1)
        }
    }
}
