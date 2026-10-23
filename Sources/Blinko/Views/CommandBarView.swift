import AppKit
import SwiftUI

/// The island as a command bar (⌥Space): input row under the notch, up to six results.
/// The panel is key while it is up (same mechanism as Notes); arrow keys, ↩ and ⎋ are read
/// by a local key monitor that exists only while this view is on screen.
struct CommandBarView: View {
    let vm: NotchViewModel
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            CommandBarHeader(vm: vm)
                .frame(height: max(vm.geometry.notchSize.height, 30))
            // Inset past the island's top-corner flares; field and row highlights share edges.
            CommandInputRow()
                .padding(.horizontal, Metrics.openTopRadius + 8)
                .padding(.top, 6)
            CommandResultsList()
                .padding(.horizontal, Metrics.openTopRadius + 8)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .onAppear(perform: activate)
        .onDisappear(perform: deactivate)
    }

    private func activate() {
        let model = CommandBarModel.shared
        model.onClose = { [weak vm] in vm?.close() }
        model.onShowTab = { [weak vm] tab in withAnimation(Motion.micro) { vm?.showTab(fromCommandBar: tab) } }
        model.prepare()
        guard monitor == nil, !model.isPreview else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 125, 48: model.moveSelection(1); return nil        // ↓, ⇥
            case 126: model.moveSelection(-1); return nil            // ↑
            case 36, 76:                                             // ↩, enter
                model.execute(alternate: event.modifierFlags.contains(.command)); return nil
            case 53: vm.close(); return nil                          // ⎋
            default: return event
            }
        }
    }

    private func deactivate() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct CommandBarHeader: View {
    let vm: NotchViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "command")
                .font(.system(size: 10, weight: .bold))
            Text("Command")
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: vm.geometry.hasNotch ? vm.geometry.notchSize.width + 16 : 16)
            KeyHint("↑↓")
            KeyHint("↩")
            KeyHint("esc")
        }
        .foregroundStyle(Color.tertiaryText)
        .padding(.horizontal, Metrics.openTopRadius + 10)
        .padding(.top, 2)
    }
}

private struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(Color.secondaryText)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.fillSubtle))
    }
}

private struct CommandInputRow: View {
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = CommandBarModel.shared
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .frame(width: 20)
            ZStack(alignment: .leading) {
                if model.isPreview {
                    HStack(spacing: 1) {
                        Text(verbatim: model.query).foregroundStyle(Color.primaryText)
                        RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 2, height: 20)
                    }
                } else {
                    TextField("", text: $model.query,
                              prompt: Text("Calculate, convert, launch or search…").foregroundStyle(Color.tertiaryText))
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.primaryText)
                        .focused($focused)
                        .onSubmit { model.execute() }
                }
            }
            .font(.system(size: 18, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            if !model.query.isEmpty, !model.isPreview {
                IslandIconButton(symbol: "xmark.circle.fill", size: 13, plate: 22, tint: .tertiaryText, help: "Clear") {
                    model.query = ""
                    focused = true
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.white.opacity(0.075))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
        .onAppear {
            // The panel became key just before; focus once the field is in the window.
            DispatchQueue.main.async { focused = true }
        }
    }
}

private struct CommandResultsList: View {
    var body: some View {
        let model = CommandBarModel.shared
        VStack(spacing: 2) {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                CommandRow(item: item, selected: index == model.selection)
                    .onTapGesture { model.execute(item) }
                    .onHover { if $0 { model.selection = index } }
            }
        }
        .animation(Motion.micro, value: model.selection)
    }
}

private struct CommandRow: View {
    let item: CommandItem
    let selected: Bool

    var body: some View {
        let isAnswer = item.kind == .calculator || item.kind == .conversion || item.kind == .currency
        HStack(spacing: 10) {
            CommandIconView(icon: item.icon)
            Text(verbatim: item.title)
                .font(.system(size: isAnswer ? 14 : 13, weight: isAnswer ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(item.kind == .placeholder ? Color.secondaryText : .primaryText)
                .lineLimit(1)
                .layoutPriority(1)
            if !item.subtitle.isEmpty {
                Text(verbatim: item.subtitle)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if selected, item.kind != .placeholder {
                HStack(spacing: 5) {
                    Text(verbatim: item.verb)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                    KeyHint("↩")
                }
                .fixedSize()
            } else {
                Text(verbatim: item.kind.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 20 pt icon: tinted SF Symbol tile, file / app icon, or an image thumbnail.
private struct CommandIconView: View {
    let icon: CommandIcon

    var body: some View {
        Group {
            switch icon {
            case .symbol(let name, let tint):
                Image(systemName: name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous).fill(tint.gradient))
            case .file(let url):
                Image(nsImage: FileIcons.icon(for: url)).resizable().interpolation(.high)
            case .image(let image):
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .frame(width: 20, height: 20)
    }
}
