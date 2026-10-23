import SwiftUI

// MARK: - Notes

/// Scratchpad + snippets. Clicking a text field makes the panel key (it is a non-activating
/// panel, so the app in front stays active); while it is key the island stays open.
struct NotesView: View {
    let vm: NotchViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Scratchpad(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SnippetsColumn(vm: vm)
                .frame(width: 210)
        }
        .onDisappear { NotesService.shared.flush() }
    }
}

private struct Scratchpad: View {
    let vm: NotchViewModel
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var notes = NotesService.shared
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(focused ? Color.fillHover : Color.fillSubtle)
            if notes.text.isEmpty {
                Text("Jot something down…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $notes.text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.primaryText)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($focused)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .onExitCommand { focused = false; vm.close() }
        }
        .animation(Motion.micro, value: focused)
        .onChange(of: focused) { _, isFocused in if isFocused { vm.requestKey?() } }
    }
}

private struct SnippetsColumn: View {
    let vm: NotchViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let notes = NotesService.shared
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.tertiaryText)
                TextField("New snippet", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.primaryText)
                    .focused($focused)
                    .onSubmit {
                        withAnimation(Motion.micro) { notes.addSnippet(draft) }
                        draft = ""
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(focused ? Color.fillHover : Color.fillSubtle))
            .onChange(of: focused) { _, isFocused in if isFocused { vm.requestKey?() } }

            if notes.snippets.isEmpty {
                Text("Save text you paste often. Click a snippet to copy it.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            } else if notes.snippets.count <= 3 {
                rows(notes.snippets)
            } else {
                ScrollView(.vertical, showsIndicators: false) { rows(notes.snippets) }
            }
        }
    }

    private func rows(_ snippets: [Snippet]) -> some View {
        VStack(spacing: 4) {
            ForEach(snippets) { snippet in
                SnippetRow(snippet: snippet)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        let notes = NotesService.shared
        HStack(spacing: 6) {
            Text(snippet.text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity)
            } else if hovering {
                Button {
                    withAnimation(Motion.micro) { notes.removeSnippet(snippet) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.secondaryText)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .help("Delete snippet")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(hovering ? Color.fillHover : Color.fillSubtle))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .onTapGesture {
            notes.copy(snippet)
            withAnimation(Motion.micro) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(Motion.micro) { copied = false } }
        }
        .help(snippet.text)
    }
}

// MARK: - Tools

struct ToolsView: View {
    let vm: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            ColorPickerCard(vm: vm)
            KeepAwakeCard()
                .frame(width: 210)
        }
    }
}

private struct ColorPickerCard: View {
    let vm: NotchViewModel

    var body: some View {
        let picker = ColorPickerService.shared
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                Button {
                    vm.isSampling = true
                    picker.pick { vm.isSampling = false }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(picker.current.map { Color(nsColor: $0.nsColor) } ?? Color.fillSubtle)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12))
                        if picker.current == nil {
                            Image(systemName: "eyedropper")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                    .frame(width: 72, height: 72)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .help("Pick a colour from the screen")
                PillButton(title: "Pick", symbol: "eyedropper", prominent: true) {
                    vm.isSampling = true
                    picker.pick { vm.isSampling = false }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if let color = picker.current {
                    ColorValueRow(label: "HEX", value: color.hex)
                    ColorValueRow(label: "RGB", value: color.rgb)
                    ColorValueRow(label: "HSL", value: color.hsl)
                } else {
                    Text("Pick any pixel on screen, then click a value to copy it.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.tertiaryText)
                        .padding(.top, 4)
                }
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    ForEach(picker.history, id: \.self) { color in
                        Circle()
                            .fill(Color(nsColor: color.nsColor))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(Color.white.opacity(color == picker.current ? 0.9 : 0.15),
                                                           lineWidth: color == picker.current ? 1.5 : 1))
                            .contentShape(Circle())
                            .onTapGesture { withAnimation(Motion.micro) { picker.select(color) } }
                            .help(color.hex)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.fillSubtle))
    }
}

private struct ColorValueRow: View {
    let label: String
    let value: String
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(Motion.micro) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation(Motion.micro) { copied = false } }
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Color.tertiaryText)
                    .frame(width: 28, alignment: .leading)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.primaryText)
                    .textSelection(.disabled)
                Spacer(minLength: 0)
                Group {
                    if copied {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    } else if hovering {
                        Image(systemName: "doc.on.doc").foregroundStyle(Color.secondaryText)
                    }
                }
                .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.fillSubtle : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help("Copy \(value)")
    }
}

private struct KeepAwakeCard: View {
    private let options: [(String, TimeInterval?)] = [("15m", 900), ("1h", 3600), ("∞", nil)]

    var body: some View {
        let awake = KeepAwakeService.shared
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(awake.isActive ? .orange : Color.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep Awake")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                    Group {
                        if !awake.isActive {
                            Text("Display sleeps normally")
                        } else if let until = awake.until {
                            Text("Until \(until, format: .dateTime.hour().minute())")
                        } else {
                            Text("Until you turn it off")
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(awake.isActive ? Color.orange.opacity(0.9) : Color.tertiaryText)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(options, id: \.0) { option in
                    PresetChip(title: option.0, compact: true) {
                        withAnimation(Motion.micro) { awake.start(for: option.1) }
                    }
                }
            }
            if awake.isActive {
                PillButton(title: "Turn Off", symbol: "xmark") {
                    withAnimation(Motion.micro) { awake.stop() }
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.fillSubtle))
    }
}
