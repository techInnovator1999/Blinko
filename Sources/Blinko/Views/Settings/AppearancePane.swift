import SwiftUI

/// Settings → Appearance: a live island preview pinned on top, themes, accent, style, size,
/// corners and type below. Every control writes a Preferences value; the preview and the real
/// islands read them through `Theme`, so changes show instantly.
struct AppearancePane: View {
    @State private var mode: ThemePreviewMode = .open
    @State private var tab: NotchTab = .home

    var body: some View {
        VStack(spacing: 0) {
            PreviewHeader(mode: $mode, tab: $tab)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 4)
            AppearanceForm()
        }
        .onAppear {
            // One off-main read of the desktop picture for the preview stage.
            if Theme.shared.wallpaperThumbnail == nil { Theme.shared.refreshWallpaper() }
        }
    }
}

// MARK: - Preview

private struct PreviewHeader: View {
    @Binding var mode: ThemePreviewMode
    @Binding var tab: NotchTab

    var body: some View {
        VStack(spacing: 8) {
            ThemePreview(mode: mode, tab: tab, width: 500)
            HStack {
                Picker("Preview", selection: $mode) {
                    ForEach(ThemePreviewMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Spacer()
                if mode == .open {
                    Picker("Tab", selection: $tab) {
                        ForEach(Preferences.shared.visibleTabs) { t in
                            Label(t.title, systemImage: t.symbol).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            .controlSize(.small)
            .frame(width: 500)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Controls

private struct AppearanceForm: View {
    @State private var importedName: String?

    var body: some View {
        @Bindable var p = Preferences.shared
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(ThemeFile.builtIns, id: \.name) { theme in
                        ThemeCard(theme: theme)
                    }
                }
                .padding(.vertical, 2)
                HStack {
                    Button("Import…") { importedName = ThemeLibrary.importTheme() }
                    Button("Export…") { ThemeLibrary.exportCurrent() }
                    if let importedName {
                        Text("Applied “\(importedName)”").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset to Defaults") { withAnimation(Motion.micro) { Theme.shared.resetToDefaults() } }
                }
            } header: {
                Text("Themes")
            } footer: {
                Text("A theme sets the accent, style, size, corners and type. Export saves yours as a small JSON file to share or keep.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                AccentRow()
            } header: {
                Text("Accent")
            } footer: {
                Text("Used for the selected tab, progress bars, the scrubber and timers. Battery, camera and microphone keep their own colours. “Wallpaper” samples your desktop picture when you switch spaces or displays.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Island style") {
                HStack(spacing: 10) {
                    ForEach(IslandStyle.allCases) { style in StyleCard(style: style) }
                }
                .padding(.vertical, 2)
            }

            Section {
                Picker("Size", selection: Binding(
                    get: { Theme.shared.sizePreset },
                    set: { preset in if let w = preset.width { withAnimation(Motion.open) { p.openWidth = w } } })) {
                    ForEach(SizePreset.choices) { Text($0.title).tag($0) }
                    if Theme.shared.sizePreset == .custom {
                        Text(SizePreset.custom.title).tag(SizePreset.custom)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Width") {
                    HStack {
                        Slider(value: $p.openWidth, in: 600...840, step: 10).frame(width: 200)
                        Text("\(Int(p.openWidth)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                    }
                }
                LabeledContent("Open corners") {
                    HStack {
                        Slider(value: $p.openCornerRadius, in: ThemeFile.openRadiusRange, step: 1) {
                            EmptyView()
                        } minimumValueLabel: { Text("Sharper").font(.caption) } maximumValueLabel: { Text("Rounder").font(.caption) }
                            .frame(width: 252)
                    }
                }
                LabeledContent("Closed corners") {
                    Slider(value: $p.closedCornerRadius, in: ThemeFile.closedRadiusRange, step: 1) {
                        EmptyView()
                    } minimumValueLabel: { Text("Sharper").font(.caption) } maximumValueLabel: { Text("Rounder").font(.caption) }
                        .frame(width: 252)
                }
                Picker("Numbers & titles", selection: $p.fontStyle) {
                    ForEach(FontStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Size & shape")
            } footer: {
                Text("Compact and Large scale the open island and its contents together. Moving the width slider (here or in Layout) makes the size Custom.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Details") {
                Toggle("Tint the player with album artwork colour", isOn: $p.artworkTint)
                Toggle("Music visualizer", isOn: $p.showVisualizer)
                Toggle("Shadow under the open island", isOn: $p.openShadow)
                Toggle("Battery in island header", isOn: $p.showBatteryInHeader)
                Toggle("“Designed by OptimaGeeks” credit", isOn: $p.showCredit)
            }

            Section {
                Toggle("Reduce motion", isOn: $p.reduceMotion)
            } header: {
                Text("Motion")
            } footer: {
                Text("Springs become short fades and the island opens without blur or scaling. Blinko also follows System Settings → Accessibility → Display → Reduce motion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Themes

private struct ThemeCard: View {
    let theme: ThemeFile
    @State private var hovering = false

    var body: some View {
        let active = ThemeLibrary.current.matches(theme)
        let accent = Color(nsColor: theme.accent == .custom
                           ? (PickedColor(hex: theme.customAccent)?.nsColor ?? .systemPink)
                           : (theme.accent.fixedColor ?? .systemPink))
        Button {
            withAnimation(Motion.open) { ThemeLibrary.apply(theme) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                MiniIsland(style: theme.style, accent: accent, radius: theme.openCornerRadius)
                    .frame(height: 46)
                HStack(spacing: 4) {
                    Text(verbatim: theme.name).font(.system(size: 11.5, weight: .semibold))
                    Spacer(minLength: 0)
                    if active {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                            .font(.system(size: 11))
                    }
                }
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? accent : Color.primary.opacity(0.08), lineWidth: active ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(theme.name)
    }
}

// MARK: - Accent

private struct AccentRow: View {
    var body: some View {
        @Bindable var p = Preferences.shared
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ForEach(AccentPreset.swatches) { preset in
                    AccentSwatch(color: Color(nsColor: preset.fixedColor ?? .white),
                                 selected: p.accentPreset == preset, help: preset.title) {
                        p.accentPreset = preset
                    }
                }
                Divider().frame(height: 18)
                CustomAccentSwatch(selected: p.accentPreset == .custom)
                Spacer()
            }
            HStack(spacing: 8) {
                MatchChip(title: "Album art", symbol: "music.note", selected: p.accentPreset == .album) {
                    p.accentPreset = .album
                }
                MatchChip(title: "Wallpaper", symbol: "photo", selected: p.accentPreset == .wallpaper) {
                    p.accentPreset = .wallpaper
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Theme.shared.accent).frame(width: 10, height: 10)
                    Text(Preferences.shared.accentPreset.title).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AccentSwatch: View {
    let color: Color
    let selected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color.gradient)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15)))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? color : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(Motion.micro, value: selected)
    }
}

/// Rainbow ring around the custom colour; clicking opens the system colour panel.
private struct CustomAccentSwatch: View {
    let selected: Bool

    var body: some View {
        let color = Color(nsColor: PickedColor(hex: Preferences.shared.customAccentHex)?.nsColor ?? .systemPink)
        Button {
            Preferences.shared.accentPreset = .custom
            CustomAccentPanel.shared.show()
        } label: {
            Circle()
                .fill(color.gradient)
                .frame(width: 16, height: 16)
                .padding(3)
                .background(Circle().strokeBorder(
                    AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center),
                    lineWidth: 3))
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? color : .clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Custom colour…")
    }
}

/// Bridges NSColorPanel to the custom accent preference.
@MainActor
private final class CustomAccentPanel: NSObject {
    static let shared = CustomAccentPanel()

    func show() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = PickedColor(hex: Preferences.shared.customAccentHex)?.nsColor ?? .systemPink
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let hex = PickedColor(sender.color)?.hex else { return }
        let p = Preferences.shared
        if p.customAccentHex != hex { p.customAccentHex = hex }
        if p.accentPreset != .custom { p.accentPreset = .custom }
    }
}

private struct MatchChip: View {
    let title: LocalizedStringKey
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(selected ? Theme.shared.accent.opacity(0.25) : Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(selected ? Theme.shared.accent : Color.primary.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Style

private struct StyleCard: View {
    let style: IslandStyle
    @State private var hovering = false

    var body: some View {
        let p = Preferences.shared
        let selected = p.islandStyle == style
        let accent = Theme.shared.accent
        Button {
            withAnimation(Motion.open) { p.islandStyle = style }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                MiniIsland(style: style, accent: accent, radius: p.openCornerRadius)
                    .frame(height: 46)
                Text(style.title).font(.system(size: 11.5, weight: .semibold))
                Text(style.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? accent : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A tiny drawing of the open island in a given style, for the theme and style cards.
private struct MiniIsland: View {
    let style: IslandStyle
    let accent: Color
    let radius: Double

    var body: some View {
        let shape = NotchShape(topRadius: style == .minimal ? 4 : 5, bottomRadius: (radius - (style == .minimal ? 6 : 0)) * 0.4)
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.32, green: 0.36, blue: 0.55), Color(red: 0.66, green: 0.5, blue: 0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                if style == .glow {
                    shape.fill(Color.black).shadow(color: accent.opacity(0.8), radius: 6, y: 2)
                }
                shape.fill(Color.black)
                if style == .glass {
                    shape.fill(LinearGradient(stops: [.init(color: .clear, location: 0.4),
                                                      .init(color: accent.opacity(0.22), location: 1)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.stroke(LinearGradient(colors: [.clear, .white.opacity(0.4)], startPoint: .top, endPoint: .bottom),
                                 lineWidth: 0.75)
                }
                // Content hints: a selected tab pill and two lines.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Capsule().fill(accent).frame(width: 9, height: 4)
                        ForEach(0..<2, id: \.self) { _ in Capsule().fill(Color.white.opacity(0.25)).frame(width: 5, height: 4) }
                    }
                    .opacity(style == .minimal ? 0.35 : 1)
                    Capsule().fill(Color.white.opacity(0.7)).frame(width: 26, height: 3)
                    Capsule().fill(accent).frame(width: 40, height: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 9)
                .padding(.top, 6)
            }
            .frame(width: 84, height: 32)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
