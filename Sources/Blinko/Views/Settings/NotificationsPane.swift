import SwiftUI

/// Settings → Notifications: mirror other apps' banners (Slack by default) into the island.
struct NotificationsPane: View {
    @State private var trusted = MediaKeyService.shared.isTrusted
    @State private var customApp = ""

    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                Toggle("Show app notifications in the island", isOn: $p.mirrorNotifications)
                if p.mirrorNotifications, !trusted {
                    HStack {
                        Label("Needs Accessibility permission", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") { MediaKeyService.shared.requestPermission() }
                    }
                }
                Toggle("Hide message text (show only who it's from)", isOn: $p.hideNotificationText)
                    .disabled(!p.mirrorNotifications)
            } footer: {
                Text("When a notification banner appears, Blinko shows it in the notch too. Click it to open the conversation. Messages never appear on the lock screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Apps") {
                ForEach(appList(p), id: \.self) { app in
                    Toggle(isOn: Binding(get: { p.mirroredApps.contains(app) }, set: { on in
                        if on { if !p.mirroredApps.contains(app) { p.mirroredApps.append(app) } }
                        else { p.mirroredApps.removeAll { $0 == app } }
                    })) {
                        HStack(spacing: 8) {
                            if let icon = NotificationMirrorService.icon(for: app) {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 18, height: 18).foregroundStyle(.secondary)
                            }
                            Text(verbatim: app)
                        }
                    }
                }
                HStack {
                    TextField("Other app (name as shown on its banners)", text: $customApp)
                        .onSubmit(addCustom)
                    Button("Add", action: addCustom).disabled(customApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .disabled(!p.mirrorNotifications)
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            let now = MediaKeyService.shared.isTrusted
            if now != trusted { trusted = now; NotificationMirrorService.shared.refresh() }
        }
    }

    private func appList(_ p: Preferences) -> [String] {
        var apps = NotificationMirrorService.suggestedApps
        for app in p.mirroredApps where !apps.contains(app) { apps.append(app) }
        return apps
    }

    private func addCustom() {
        let name = customApp.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let p = Preferences.shared
        if !p.mirroredApps.contains(name) { p.mirroredApps.append(name) }
        customApp = ""
    }
}
