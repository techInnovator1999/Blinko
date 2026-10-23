import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case welcome, general, activities, modules, appearance, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .general: "General"
        case .activities: "Live Activities"
        case .modules: "Modules"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .general: "gearshape.fill"
        case .activities: "waveform"
        case .modules: "square.grid.2x2.fill"
        case .appearance: "paintbrush.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: .pink
        case .general: .gray
        case .activities: .orange
        case .modules: .blue
        case .appearance: .purple
        case .about: .teal
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(pane: SettingsPane? = nil) {
        if let pane { selection.pane = pane }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(selection: selection))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
@Observable
final class SettingsSelection {
    var pane: SettingsPane = .general
}

struct SettingsView: View {
    @Bindable var selection: SettingsSelection

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { selection.pane }, set: { if let p = $0 { selection.pane = p } })) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(pane.tint.gradient))
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch selection.pane {
                case .welcome: WelcomePane(selection: selection)
                case .general: GeneralPane()
                case .activities: ActivitiesPane()
                case .modules: ModulesPane()
                case .appearance: AppearancePane()
                case .about: AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

// MARK: - Panes

private struct WelcomePane: View {
    let selection: SettingsSelection
    @State private var trusted = MediaKeyService.shared.isTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Capsule().fill(.black).frame(width: 74, height: 26)
                    .overlay(Capsule().stroke(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Blinko").font(.system(size: 24, weight: .bold))
                    Text("Your notch, alive. Hover it, swipe down on it, or press ⌃⌥Space.")
                        .foregroundStyle(.secondary)
                }
            }
            PermissionRow(symbol: "keyboard", title: "Accessibility",
                          detail: "Needed to replace the volume & brightness HUD.",
                          granted: trusted) {
                MediaKeyService.shared.requestPermission()
            }
            PermissionRow(symbol: "calendar", title: "Calendar & Reminders",
                          detail: "Shows your next events and meeting links.",
                          granted: CalendarService.shared.authorized) {
                CalendarService.shared.requestAccess()
            }
            Spacer()
            HStack {
                Spacer()
                Button("Get Started") {
                    Preferences.shared.hasCompletedOnboarding = true
                    selection.pane = .general
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(28)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            trusted = MediaKeyService.shared.isTrusted
        }
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Grant…", action: action)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quinary))
    }
}

private struct GeneralPane: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, v in LaunchAtLogin.isEnabled = v }
                Toggle("Show menu bar icon", isOn: $p.showMenuBarIcon)
            }
            Section("Displays") {
                Picker("Show island on", selection: $p.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Hide when an app is fullscreen", isOn: $p.hideInFullscreen)
            }
            Section("Interaction") {
                Toggle("Open on hover", isOn: $p.openOnHover)
                if p.openOnHover {
                    LabeledContent("Hover delay") {
                        Slider(value: $p.hoverDelay, in: 0...0.6, step: 0.02) {
                            EmptyView()
                        } minimumValueLabel: { Text("Instant").font(.caption) } maximumValueLabel: { Text("0.6s").font(.caption) }
                            .frame(width: 220)
                    }
                }
                Toggle("Close when the pointer leaves", isOn: $p.closeOnMouseExit)
                Toggle("Swipe gestures (two-finger down/up)", isOn: $p.enableGestures)
                Toggle("Haptic feedback", isOn: $p.enableHaptics)
                LabeledContent("Toggle shortcut", value: "⌃⌥Space")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ActivitiesPane: View {
    @State private var trusted = MediaKeyService.shared.isTrusted

    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                Toggle("Now Playing", isOn: $p.musicActivity)
                Toggle("Battery & charging", isOn: $p.batteryActivity)
                Toggle("Bluetooth devices", isOn: $p.bluetoothActivity)
            } header: {
                Text("Show in the closed island")
            }
            Section {
                Toggle("Replace system volume & brightness HUD", isOn: $p.replaceSystemHUD)
                if p.replaceSystemHUD, !trusted {
                    HStack {
                        Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") { MediaKeyService.shared.requestPermission() }
                    }
                }
            } header: {
                Text("HUD")
            } footer: {
                Text("Hold ⌥⇧ while pressing a key for fine-grained steps. ⌥ alone opens the related System Settings pane.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            trusted = MediaKeyService.shared.isTrusted
        }
    }
}

private struct ModulesPane: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section("Home") {
                Toggle("Calendar & reminders", isOn: $p.showCalendar)
                Toggle("Camera mirror", isOn: $p.showMirror)
            }
            Section("Shelf") {
                Toggle("Open shelf when dragging files onto the notch", isOn: $p.shelfAutoOpenOnDrag)
                Button("Clear shelf") { ShelfService.shared.clear() }
            }
            Section {
                Toggle("Keep clipboard history", isOn: $p.clipboardHistory)
                Stepper("Keep \(p.clipboardLimit) items", value: $p.clipboardLimit, in: 5...100, step: 5)
                    .disabled(!p.clipboardHistory)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("History stays in memory only. Items marked as passwords by password managers are never recorded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearancePane: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                Toggle("Tint controls with album artwork colour", isOn: $p.artworkTint)
                Toggle("Music visualizer", isOn: $p.showVisualizer)
                Toggle("Shadow under the open island", isOn: $p.openShadow)
                Toggle("Battery in island header", isOn: $p.showBatteryInHeader)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 10) {
            Capsule().fill(.black).frame(width: 120, height: 38)
                .overlay(Capsule().stroke(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 40)
            Text("Blinko").font(.system(size: 26, weight: .bold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("A fast, native Dynamic Island for the Mac.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit Blinko") { NSApp.terminate(nil) }.padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}
