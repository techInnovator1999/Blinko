import AppKit
import CoreLocation
import SwiftUI

// MARK: - 5 · Permissions

/// One row per permission, each with its reason and its own button: nothing is requested until
/// the user asks for that one. Optional features stay off unless turned on here or in Settings.
struct PermissionsStep: View {
    @State private var trusted = MediaKeyService.shared.isTrusted

    var body: some View {
        let p = Preferences.shared
        let calendar = CalendarService.shared
        let focus = FocusService.shared
        let weather = WeatherService.shared
        VStack(spacing: 0) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.shared.accent.gradient))
                .padding(.top, 8)
            Text("Only what you choose")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 14)
            Text("Each permission unlocks one feature. Blinko asks for nothing on its own, and everything stays on your Mac.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 7) {
                SectionCaption(title: "Recommended")
                PermissionCard(symbol: "speaker.wave.2.fill", tint: .pink, title: "Accessibility",
                               why: "Replaces the volume and brightness HUD with the island's own.",
                               state: trusted ? .granted : .available, button: "Grant…") {
                    MediaKeyService.shared.requestPermission()
                }
                PermissionCard(symbol: "calendar", tint: .red, title: "Calendar & Reminders",
                               why: "Shows your next events and one-click meeting links on Home.",
                               state: calendar.authorized ? .granted : (calendar.denied ? .denied("Privacy_Calendars") : .available),
                               button: "Grant…") {
                    calendar.requestAccess()
                }
                SectionCaption(title: "Optional").padding(.top, 6)
                PermissionCard(symbol: "moon.fill", tint: .indigo, title: "Focus",
                               why: "Shows when a Focus or Do Not Disturb turns on or off.",
                               state: focus.readsDatabase || focus.authorization == .authorized ? .granted
                                   : (focus.authorization == .denied ? .denied("Privacy_Focus") : .available),
                               button: "Allow…") {
                    p.focusActivity = true
                    focus.requestAuthorization()
                }
                PermissionCard(symbol: "arrow.down.circle.fill", tint: .blue, title: "Download progress",
                               why: "Follows downloads in ~/Downloads. macOS asks for access to that folder.",
                               state: p.downloadsActivity ? .on : .available, button: "Turn On") {
                    p.downloadsActivity = true
                }
                PermissionCard(symbol: "location.fill", tint: .teal, title: "Weather",
                               why: "Uses your approximate location once per session. You can pick a city in Settings instead.",
                               state: !p.weatherEnabled ? .available
                                   : (weather.locationStatus == .denied ? .denied("Privacy_LocationServices") : .on),
                               button: "Turn On") {
                    p.weatherUseLocation = true
                    p.weatherEnabled = true
                }
            }
            .frame(maxWidth: 600)
            .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .onAppear { focus.recheckAccess() }
        // Accessibility has no change notification; poll only while this page is visible.
        .onReceive(Timer.publish(every: 1.5, tolerance: 0.5, on: .main, in: .common).autoconnect()) { _ in
            let now = MediaKeyService.shared.isTrusted
            if now != trusted { trusted = now }
        }
    }
}

private struct SectionCaption: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }
}

enum PermissionState: Equatable {
    case available, granted, on
    /// Denied earlier: the button opens that System Settings privacy pane instead.
    case denied(String)
}

private struct PermissionCard: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let why: LocalizedStringKey
    let state: PermissionState
    let button: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(why).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch state {
            case .granted:
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                    .fixedSize()
            case .on:
                Label("On", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                    .fixedSize()
            case .denied(let pane):
                Button("Open Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
                }
                .controlSize(.small)
                .fixedSize()
            case .available:
                Button(button, action: action)
                    .controlSize(.small)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(TourCardBackground(highlighted: false))
        .animation(Motion.micro, value: state)
    }
}
