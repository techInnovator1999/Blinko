import SwiftUI

/// Settings → Lock Screen (experimental, off by default).
struct LockScreenPane: View {
    private let available = SkyLightSpace.shared.isAvailable

    var body: some View {
        @Bindable var s = LockScreenSettings.shared
        Form {
            Section {
                Toggle("Show Blinko on the lock screen", isOn: $s.enabled)
                    .disabled(!available)
                if !available {
                    Label("Not available on this version of macOS", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                HStack(spacing: 6) {
                    Text("Lock Screen")
                    Text("Experimental")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Uses a private macOS window-server feature (the one other notch apps use) to draw the island and widgets above the lock screen. Apple may change or remove it in any update; Blinko then simply turns this off. Nothing runs while your Mac is unlocked.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Island at the notch", isOn: $s.showIsland)
                Group {
                    Toggle("Now Playing (tap to expand the player)", isOn: $s.islandMusic)
                    Toggle("Charging", isOn: $s.islandCharging)
                    Toggle("Timers & Pomodoro", isOn: $s.islandTimer)
                }
                .padding(.leading, 16)
                .disabled(!s.showIsland)
            } header: {
                Text("Island")
            } footer: {
                Text("On the lock screen the island never opens on hover; a tap opens only the music player. Volume, brightness, Caps Lock and battery alerts still appear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!s.enabled)

            Section {
                Toggle("Widget panel", isOn: $s.showWidgets)
                Group {
                    Toggle("Now Playing with controls", isOn: $s.widgetMusic)
                    Toggle("Battery", isOn: $s.widgetBattery)
                    Toggle("Next calendar event", isOn: $s.widgetCalendar)
                    Toggle("Active timer", isOn: $s.widgetTimer)
                    LabeledContent("Vertical position") {
                        Slider(value: $s.widgetOffset, in: -200...200, step: 10)
                            .frame(width: 180)
                    }
                }
                .padding(.leading, 16)
                .disabled(!s.showWidgets)
            } header: {
                Text("Widgets")
            } footer: {
                Text("A row of cards below the middle of your main display. Each card appears only when it has something to show.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!s.enabled)

            Section {
                Toggle("Show calendar details on lock screen", isOn: $s.calendarDetails)
                Toggle("Show AI agent status on lock screen", isOn: $s.showAgents)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Anyone near your Mac can see the lock screen. Without details, the next event shows only its time. Clipboard, shelf, notes, downloads, meetings and custom alerts are never shown there.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!s.enabled)
        }
        .formStyle(.grouped)
    }
}
