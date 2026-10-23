import SwiftUI

/// Settings → Sounds: one switch and one sound per event, with previews.
struct SoundsPane: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                Toggle("Play notification sounds", isOn: $p.soundsEnabled)
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $p.soundVolume, in: 0.1...1) { editing in
                            if !editing { SoundService.shared.preview(.blink) }
                        }
                        .frame(width: 200)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                .disabled(!p.soundsEnabled)
                Toggle("Silence sounds while Focus is on", isOn: $p.silenceSoundsInFocus)
                    .disabled(!p.soundsEnabled)
            } footer: {
                Text("Permission requests, “you’re muted” and low battery still sound during Focus.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Sound library") {
                SoundLibrary()
            }

            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(SoundEvent.allCases.filter { $0.group == group }) { event in
                        SoundEventRow(event: event)
                    }
                }
                .disabled(!p.soundsEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var groups: [String] {
        var seen: [String] = []
        for e in SoundEvent.allCases where !seen.contains(e.group) { seen.append(e.group) }
        return seen
    }
}

private struct SoundEventRow: View {
    let event: SoundEvent

    var body: some View {
        let p = Preferences.shared
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { p.isSoundOn(event) }, set: { p.setSound(event, on: $0) })) {
                Text(event.title)
            }
            Spacer()
            Picker("", selection: Binding(get: { p.sound(for: event) }, set: {
                p.setSound(event, to: $0)
                SoundService.shared.preview($0)
            })) {
                ForEach(NotificationSound.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 110)
            .disabled(!p.isSoundOn(event))
            Button {
                SoundService.shared.preview(p.sound(for: event))
            } label: {
                Image(systemName: "play.circle.fill").font(.system(size: 17))
            }
            .buttonStyle(.borderless)
            .help("Preview")
            .disabled(!p.isSoundOn(event) || p.sound(for: event) == .none)
        }
    }
}

/// Tap any chip to hear it.
private struct SoundLibrary: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(NotificationSound.allCases.filter { $0 != .none }) { sound in
                Button {
                    SoundService.shared.preview(sound)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                        Text(sound.title).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
