import SwiftUI

/// Settings → Home Layout: a live, editable island preview with a widget palette pinned on
/// top, layout management and a list editor (the keyboard / VoiceOver path) below.
/// Every change goes through `HomeLayouts`, so the real islands follow instantly.
struct HomeLayoutPane: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HomeLayoutPreview(width: 510)
                WidgetPalette()
                    .frame(width: 510)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            HomeLayoutForm()
        }
        .onAppear {
            // One off-main read of the desktop picture for the preview stage.
            if Theme.shared.wallpaperThumbnail == nil { Theme.shared.refreshWallpaper() }
        }
    }
}

// MARK: - Preview

/// The real island (its own view model, always open on Home) in edit mode: drop widgets from
/// the palette onto it, drag slots to reorder, S / M / L to resize, × to remove.
struct HomeLayoutPreview: View {
    var width: CGFloat = 510
    @State private var vm = ThemePreview.makeViewModel()

    static let stage = CGSize(width: 780, height: 240)

    var body: some View {
        let scale = width / Self.stage.width
        ZStack(alignment: .top) {
            HomePreviewDesktop()
            NotchRootView(vm: vm)
                .frame(width: Self.stage.width, height: Self.stage.height)
                .environment(\.homeLayoutEditing, true)
        }
        .frame(width: Self.stage.width, height: Self.stage.height)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: width, height: Self.stage.height * scale, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .onAppear { vm.open(tab: .home) }
        // The header's gear / pin can close the preview island, its tabs can leave Home.
        .onChange(of: vm.isOpen) { _, open in if !open { vm.open(tab: .home) } }
        .onChange(of: vm.tab) { _, tab in if tab != .home { vm.tab = .home } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home layout preview")
    }
}

private struct HomePreviewDesktop: View {
    var body: some View {
        ZStack(alignment: .top) {
            if let wallpaper = Theme.shared.wallpaperThumbnail {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: HomeLayoutPreview.stage.width, height: HomeLayoutPreview.stage.height)
                    .clipped()
            } else {
                LinearGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.5), Color(red: 0.62, green: 0.45, blue: 0.58)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Rectangle().fill(.black.opacity(0.22)).frame(height: 32)
        }
    }
}

// MARK: - Palette

/// Every widget as a chip: drag it onto the preview, or click to add it at the end.
private struct WidgetPalette: View {
    var body: some View {
        let layout = HomeLayouts.current
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], spacing: 6) {
            ForEach(HomeWidgetKind.allCases) { kind in
                PaletteChip(kind: kind, fits: layout.fittingSize(for: kind) != nil,
                            agentHubOff: kind == .agents && !Preferences.shared.agentHubEnabled)
            }
        }
    }
}

private struct PaletteChip: View {
    let kind: HomeWidgetKind
    let fits: Bool
    let agentHubOff: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(kind.tint.gradient))
            Text(kind.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.1 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .opacity(fits ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { withAnimation(Motion.micro) { _ = HomeLayouts.add(kind) } }
        .draggable(HomeDragItem.widget(kind)) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.regularMaterial))
        }
        .help(help)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Add \(kind.title)"))
    }

    private var help: String {
        var parts = [kind.subtitle + " (" + kind.sizes.map(\.letter).joined(separator: " / ") + ")."]
        if agentHubOff { parts.append(String(localized: "Needs the Agent Hub (Settings → Agents).")) }
        parts.append(fits ? String(localized: "Click to add, or drag onto the preview.")
                          : String(localized: "Home is full: drop it on a widget to replace it."))
        return parts.joined(separator: " ")
    }
}

// MARK: - Form

private struct HomeLayoutForm: View {
    @State private var name = ""

    var body: some View {
        let layout = HomeLayouts.current
        Form {
            Section {
                Picker("Layout", selection: Binding(get: { layout.id }, set: { id in
                    withAnimation(Motion.micro) { HomeLayouts.select(id) }
                })) {
                    ForEach(HomeLayout.builtIns) { Text(verbatim: $0.name).tag($0.id) }
                    if !Preferences.shared.homeLayouts.isEmpty {
                        Divider()
                        ForEach(Preferences.shared.homeLayouts) { Text(verbatim: $0.name).tag($0.id) }
                    }
                }
                if !layout.isBuiltIn {
                    LabeledContent("Name") {
                        TextField("Name", text: $name, prompt: Text(verbatim: layout.name))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .onSubmit { HomeLayouts.rename(name) }
                            .labelsHidden()
                    }
                }
                LabeledContent("Room") { CapacityMeter(layout: layout) }
                HStack {
                    Button("Duplicate") { withAnimation(Motion.micro) { HomeLayouts.duplicateCurrent() } }
                    if !layout.isBuiltIn {
                        Button("Delete", role: .destructive) { withAnimation(Motion.micro) { HomeLayouts.deleteCurrent() } }
                    }
                    Spacer()
                    if layout.id != HomeLayout.defaultID {
                        Button("Use Default") { withAnimation(Motion.micro) { HomeLayouts.select(HomeLayout.defaultID) } }
                    }
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Default is the classic Home and follows the Home toggles in Modules. Editing a built-in layout saves your version as a new layout. Right-click the Home tab button in the island to switch layouts.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if layout.slots.isEmpty {
                    Text("No widgets yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(layout.slots.enumerated()), id: \.element.id) { index, slot in
                    SlotRow(slot: slot, index: index, layout: layout)
                }
                Menu {
                    ForEach(HomeWidgetKind.allCases) { kind in
                        Button {
                            withAnimation(Motion.micro) { _ = HomeLayouts.add(kind) }
                        } label: {
                            Label(kind.title, systemImage: kind.symbol)
                        }
                        .disabled(layout.fittingSize(for: kind) == nil)
                    }
                } label: {
                    Label("Add Widget", systemImage: "plus")
                }
                .fixedSize()
                .disabled(layout.freeUnits < HomeWidgetSize.small.units)
            } header: {
                Text("Widgets")
            } footer: {
                Text("Left to right as on the island. Small takes 2 of the 10 units, Medium 3 and Large 5; Large widgets share the room that is left. Widgets that are not on Home do no work at all.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { name = layout.name }
        .onChange(of: layout.id) { _, _ in name = HomeLayouts.current.name }
    }
}

/// How many of the 10 units the layout uses, as segments.
private struct CapacityMeter: View {
    let layout: HomeLayout

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Array(layout.slots.enumerated()), id: \.element.id) { _, slot in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(slot.widget.tint.gradient)
                        .frame(width: CGFloat(slot.size.units) * 12 - 2, height: 10)
                        .help("\(slot.widget.title) · \(slot.size.title)")
                }
                if layout.freeUnits > 0 {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: CGFloat(layout.freeUnits) * 12 - 2, height: 10)
                }
            }
            Text("\(layout.units) of \(HomeLayout.capacity) units")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(layout.units) of \(HomeLayout.capacity) units used"))
    }
}

/// One widget in the list: size menu, move left / right, remove.
private struct SlotRow: View {
    let slot: HomeSlot
    let index: Int
    let layout: HomeLayout

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: slot.widget.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(slot.widget.tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.widget.title)
                Text(slot.widget.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(slot.widget.sizes) { size in
                    Button {
                        withAnimation(Motion.micro) { HomeLayouts.resize(slot.id, to: size) }
                    } label: {
                        if size == slot.size {
                            Label(size.title, systemImage: "checkmark")
                        } else {
                            Text(size.title)
                        }
                    }
                    .disabled(!layout.canResize(slot, to: size))
                }
            } label: {
                Text(slot.size.title)
            }
            .fixedSize()
            .disabled(slot.widget.sizes.count < 2)
            .accessibilityLabel(Text("Size of \(slot.widget.title): \(slot.size.title)"))
            ControlGroup {
                Button {
                    withAnimation(Motion.micro) { HomeLayouts.move(slot.id, to: index - 1) }
                } label: { Image(systemName: "chevron.left") }
                    .disabled(index == 0)
                    .help("Move left")
                    .accessibilityLabel(Text("Move \(slot.widget.title) left"))
                Button {
                    withAnimation(Motion.micro) { HomeLayouts.move(slot.id, to: index + 1) }
                } label: { Image(systemName: "chevron.right") }
                    .disabled(index == layout.slots.count - 1)
                    .help("Move right")
                    .accessibilityLabel(Text("Move \(slot.widget.title) right"))
            }
            .fixedSize()
            Button {
                withAnimation(Motion.micro) { HomeLayouts.remove(slot.id) }
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
            .accessibilityLabel(Text("Remove \(slot.widget.title)"))
        }
    }
}
