import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case welcome, general, activities, modules, layout, appearance, meetings, commandBar
    case homeLayout
    case agents, automation
    case lockScreen
    case sounds
    case about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome")
        case .general: String(localized: "General")
        case .activities: String(localized: "Live Activities")
        case .modules: String(localized: "Modules")
        case .layout: String(localized: "Layout")
        case .appearance: String(localized: "Appearance")
        case .meetings: String(localized: "Meetings")
        case .commandBar: String(localized: "Command Bar")
        case .about: String(localized: "About")
        case .agents: String(localized: "Agents")
        case .automation: String(localized: "Automation")
        case .lockScreen: String(localized: "Lock Screen")
        case .sounds: String(localized: "Sounds")
        case .homeLayout: String(localized: "Home Layout")
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .general: "gearshape.fill"
        case .activities: "waveform"
        case .modules: "square.grid.2x2.fill"
        case .layout: "rectangle.3.group.fill"
        case .appearance: "paintbrush.fill"
        case .meetings: "video.fill"
        case .commandBar: "command"
        case .about: "info.circle.fill"
        case .agents: "sparkles.rectangle.stack.fill"
        case .automation: "bolt.horizontal.fill"
        case .lockScreen: "lock.fill"
        case .sounds: "speaker.wave.2.fill"
        case .homeLayout: "square.grid.3x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: .pink
        case .general: .gray
        case .activities: .orange
        case .modules: .blue
        case .layout: .indigo
        case .appearance: .purple
        case .meetings: .green
        case .commandBar: .pink
        case .about: .teal
        case .agents: .agentAccent
        case .automation: .green
        case .lockScreen: .blue
        case .sounds: .pink
        case .homeLayout: .cyan
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(pane: SettingsPane? = nil) {
        // The old Welcome pane is now the guided tour (its own window).
        if pane == .welcome { OnboardingWindowController.shared.show(); return }
        if let pane { selection.pane = pane }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 580),
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
    var query = ""
}

struct SettingsView: View {
    @Bindable var selection: SettingsSelection

    var body: some View {
        NavigationSplitView {
          Group {
            if !selection.query.trimmingCharacters(in: .whitespaces).isEmpty {
                SettingsSearchResults(query: selection.query) { entry in
                    selection.pane = entry.pane
                    let window = NSApp.keyWindow
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        SettingsHighlighter.reveal(entry.title, in: window)
                    }
                }
            } else {
            List(SettingsPane.allCases.filter { $0 != .welcome }, selection: Binding(get: { selection.pane }, set: { if let p = $0 { selection.pane = p } })) { pane in
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
            }
          }
          .searchable(text: $selection.query, placement: .sidebar, prompt: Text("Search settings"))
          .navigationSplitViewColumnWidth(220)
        } detail: {
            Group {
                switch selection.pane {
                case .welcome: EmptyView() // never selected: see show(pane:)
                case .general: GeneralPane()
                case .activities: ActivitiesPane()
                case .modules: ModulesPane()
                case .layout: LayoutPane()
                case .appearance: AppearancePane()
                case .meetings: MeetingsPane()
                case .commandBar: CommandBarPane()
                case .about: AboutPane()
                case .agents: AgentsSettingsPane()
                case .automation: AutomationSettingsPane()
                case .lockScreen: LockScreenPane()
                case .sounds: SoundsPane()
                case .homeLayout: HomeLayoutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

// MARK: - Panes

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
                Toggle("Global shortcut", isOn: $p.hotkeyEnabled)
                if p.hotkeyEnabled {
                    LabeledContent("Toggle island") { HotkeyRecorder() }
                }
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
                Toggle("AirPods battery levels", isOn: $p.airPodsBattery)
                    .disabled(!p.bluetoothActivity)
            } header: {
                Text("Show in the closed island")
            }
            Section {
                Toggle("Focus & Do Not Disturb", isOn: $p.focusActivity)
                if p.focusActivity { FocusAccessRow() }
                Toggle("Camera & microphone in use", isOn: $p.privacyIndicators)
                Toggle("Wi-Fi, VPN & Personal Hotspot", isOn: $p.networkActivity)
                Toggle("Download progress", isOn: $p.downloadsActivity)
            } header: {
                Text("Awareness")
            } footer: {
                Text("Camera and microphone show a green or orange dot at the edge of the island while in use. Downloads from Safari, Chrome and Firefox are followed in ~/Downloads; macOS asks for access to that folder the first time. AirPods levels use undocumented Bluetooth properties and may not appear for every model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Replace system volume & brightness HUD", isOn: $p.replaceSystemHUD)
                Toggle("Caps Lock indicator", isOn: $p.capsLockHUD)
                Toggle("Microphone volume & mute", isOn: $p.micHUD)
                if p.replaceSystemHUD || p.capsLockHUD, !trusted {
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

/// Focus needs either the user's Focus Status authorization (on/off only) or Full Disk
/// Access (adds the mode's name and icon). Shows what is available and how to get more.
private struct FocusAccessRow: View {
    var body: some View {
        let focus = FocusService.shared
        HStack {
            if focus.readsDatabase {
                Label("Mode names available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else if focus.authorization == .authorized {
                Label("On / off only", systemImage: "checkmark.circle").foregroundStyle(.secondary)
            } else {
                Label("Focus Status access needed", systemImage: "moon.fill").foregroundStyle(.secondary)
            }
            Spacer()
            if focus.authorization != .authorized, !focus.readsDatabase {
                Button(focus.authorization == .denied ? "Open Settings" : "Allow…") {
                    if focus.authorization == .denied {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Focus")!)
                    } else {
                        focus.requestAuthorization()
                    }
                }
            } else if !focus.readsDatabase {
                Button("Show Names…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                .help("Grant Full Disk Access to Blinko to show the Focus mode's name")
            }
        }
        .font(.callout)
        .onAppear { focus.recheckAccess() }
    }
}

private struct ModulesPane: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section("Clock") {
                Toggle("Clock on Home", isOn: $p.showClock)
                Toggle("Time in island header", isOn: $p.showClockInHeader)
                Toggle("Time & date in the closed island when idle", isOn: $p.showClockWhenIdle)
            }
            WorldClocksSection()
            WeatherSection()
            Section {
                Toggle("Synced lyrics in the player", isOn: $p.showLyrics)
                Toggle("Lyrics in the closed island", isOn: $p.compactLyrics)
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Time-synced lyrics from LRCLIB, fetched when a new track starts while lyrics are on screen, and cached on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Calendar & reminders", isOn: $p.showCalendar)
                Toggle("Camera mirror", isOn: $p.showMirror)
            } header: {
                Text("Home")
            } footer: {
                Text("These shape the Default Home layout. Other layouts and your own are in Home Layout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Stepper("Focus: \(p.focusMinutes) min", value: $p.focusMinutes, in: 5...90, step: 5)
                Stepper("Short break: \(p.shortBreakMinutes) min", value: $p.shortBreakMinutes, in: 1...30)
                Stepper("Long break: \(p.longBreakMinutes) min", value: $p.longBreakMinutes, in: 5...60, step: 5)
                Toggle("Start the next session automatically", isOn: $p.autoStartNextSession)
            } header: {
                Text("Focus (Pomodoro)")
            } footer: {
                Text("A long break follows every fourth focus session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Notes tab", isOn: tabVisible(.notes))
                Toggle("Tools tab (colour picker, Keep Awake)", isOn: tabVisible(.tools))
                Button("Clear colour history") { ColorPickerService.shared.clearHistory() }
            } header: {
                Text("Notes & Tools")
            } footer: {
                Text("Notes and snippets are saved in ~/Library/Application Support/Blinko. Keep Awake stops when Blinko quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open shelf when dragging files onto the notch", isOn: $p.shelfAutoOpenOnDrag)
                Picker("Remove items from the shelf", selection: $p.shelfExpiryDays) {
                    Text("Never").tag(0)
                    Text("After 1 day").tag(1)
                    Text("After 1 week").tag(7)
                }
                Button("Clear shelf") { ShelfService.shared.clear() }
            } header: {
                Text("Shelf")
            } footer: {
                Text("Click files to select several, then drag any selected file to move them all. Only the shelf entries expire — your files stay where they are.")
                    .font(.caption).foregroundStyle(.secondary)
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

/// Shows / hides a tab (same rule as the Layout pane: one tab always stays visible).
@MainActor
private func tabVisible(_ tab: NotchTab) -> Binding<Bool> {
    let p = Preferences.shared
    return Binding(get: { !p.hiddenTabs.contains(tab) }, set: { visible in
        if visible { p.hiddenTabs.remove(tab) } else if p.visibleTabs.count > 1 { p.hiddenTabs.insert(tab) }
    })
}

private struct WorldClocksSection: View {
    @State private var picking = false

    var body: some View {
        @Bindable var p = Preferences.shared
        Section {
            ForEach(p.worldClocks, id: \.self) { id in
                HStack {
                    if let zone = TimeZone(identifier: id) {
                        Text(WorldClock.city(zone))
                        Text(zone.localizedName(for: .shortGeneric, locale: .current) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        p.worldClocks.removeAll { $0 == id }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove")
                }
            }
            if p.worldClocks.count < 3 {
                Button("Add Time Zone…") { picking = true }
                    .popover(isPresented: $picking, arrowEdge: .trailing) {
                        TimeZonePicker { id in
                            if !p.worldClocks.contains(id), p.worldClocks.count < 3 { p.worldClocks.append(id) }
                            picking = false
                        }
                    }
            }
        } header: {
            Text("World clocks")
        } footer: {
            Text("Up to three, shown under the clock on Home.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct TimeZonePicker: View {
    let choose: (String) -> Void
    @State private var query = ""

    private static let all = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !$0.hasPrefix("Etc/") }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = q.isEmpty ? Self.all : Self.all.filter {
            $0.lowercased().replacingOccurrences(of: "_", with: " ").contains(q)
        }
        VStack(spacing: 0) {
            TextField("Search cities", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            List(matches, id: \.self) { id in
                Button {
                    choose(id)
                } label: {
                    HStack {
                        Text(WorldClock.city(TimeZone(identifier: id)!))
                        Spacer()
                        Text(id.split(separator: "/").first.map(String.init) ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 300, height: 340)
    }
}

private struct WeatherSection: View {
    @State private var query = ""
    @State private var results: [WeatherService.City] = []
    @State private var searching = false

    var body: some View {
        @Bindable var p = Preferences.shared
        let weather = WeatherService.shared
        Section {
            Toggle("Show weather", isOn: $p.weatherEnabled)
            if p.weatherEnabled {
                Picker("Location", selection: Binding(get: { p.weatherUseLocation }, set: {
                    p.weatherUseLocation = $0
                    weather.locationSettingsChanged()
                })) {
                    Text("Current location").tag(true)
                    Text("City").tag(false)
                }
                if p.weatherUseLocation, weather.locationStatus == .denied || weather.locationStatus == .restricted {
                    HStack {
                        Label("Location access is off — the city below is used instead.", systemImage: "location.slash")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                        }
                    }
                    .font(.callout)
                }
                if !p.weatherUseLocation || weather.locationStatus == .denied || weather.locationStatus == .restricted {
                    LabeledContent("City") {
                        HStack {
                            TextField("Search", text: $query, prompt: Text(p.weatherCity.isEmpty ? "Search for a city" : p.weatherCity))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                                .onSubmit(search)
                            Button("Search", action: search).disabled(query.count < 2 || searching)
                        }
                    }
                    ForEach(results) { city in
                        Button {
                            p.weatherCity = city.name
                            p.weatherLatitude = city.latitude
                            p.weatherLongitude = city.longitude
                            results = []
                            query = ""
                            weather.locationSettingsChanged()
                        } label: {
                            HStack {
                                Text(city.name)
                                Text(city.detail).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let report = weather.report {
                    LabeledContent("Now") {
                        Text("\(Temperature.format(report.temperature)) · \(WeatherCode.description(report.code))")
                            .foregroundStyle(.secondary)
                    }
                } else if weather.failed {
                    Text("Couldn't load the weather. Blinko retries every 30 minutes.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("Forecasts from Open-Meteo, refreshed every 30 minutes while Blinko runs. Your location is used once per session and only sent to Open-Meteo as rounded coordinates.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func search() {
        let q = query
        searching = true
        Task {
            let found = await WeatherService.searchCities(q)
            results = found
            searching = false
        }
    }
}

private struct LayoutPane: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                LabeledContent("Open width") {
                    HStack {
                        Slider(value: $p.openWidth, in: 600...840, step: 10).frame(width: 220)
                        Text("\(Int(p.openWidth)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                    }
                }
                LabeledContent("Closed width fine-tune") {
                    HStack {
                        Slider(value: $p.notchWidthOffset, in: -12...40, step: 1).frame(width: 220)
                        Text(String(format: "%+d pt", Int(p.notchWidthOffset))).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                    }
                }
                Button("Reset sizes") {
                    p.openWidth = 700
                    p.notchWidthOffset = 0
                }
            } header: {
                Text("Island size")
            } footer: {
                Text("Fine-tune makes the closed island exactly cover your notch — handy for scaled display resolutions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                List {
                    ForEach(p.tabOrder) { tab in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Image(systemName: tab.symbol).frame(width: 20)
                            Text(tab.title)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !p.hiddenTabs.contains(tab) },
                                set: { visible in
                                    if visible { p.hiddenTabs.remove(tab) }
                                    else if p.visibleTabs.count > 1 { p.hiddenTabs.insert(tab) }
                                }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    .onMove { p.tabOrder.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: CGFloat(p.tabOrder.count) * 34)
            } header: {
                Text("Tabs")
            } footer: {
                Text("Drag to reorder. At least one tab stays visible.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesSection: View {
    @State private var automatic = UpdateService.shared.automaticallyChecks

    var body: some View {
        let updates = UpdateService.shared
        if updates.isConfigured {
            VStack(spacing: 8) {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)
                Toggle("Automatically check for updates", isOn: $automatic)
                    .onChange(of: automatic) { _, v in updates.automaticallyChecks = v }
                    .toggleStyle(.checkbox)
            }
        } else {
            Text("Updates are disabled in this development build.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 10) {
            AppIconView(size: 128)
                .padding(.top, 28)
            Text("Blinko").font(.system(size: 26, weight: .bold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("A fast, native Dynamic Island for the Mac.")
                .foregroundStyle(.secondary)
            UpdatesSection().padding(.top, 12)
            HStack(spacing: 10) {
                Button("Show Tour") { OnboardingWindowController.shared.show() }
                Menu("Send Feedback") {
                    Button("Report a Bug…") { Feedback.open(.bug) }
                    Button("Request a Feature…") { Feedback.open(.feature) }
                }
                .fixedSize()
            }
            .padding(.top, 8)
            Text("Feedback opens a pre-filled GitHub issue you can review before sending. Blinko collects no analytics.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
            Button("Quit Blinko") { NSApp.terminate(nil) }.padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}
