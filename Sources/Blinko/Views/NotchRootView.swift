import SwiftUI
import UniformTypeIdentifiers

struct NotchRootView: View {
    let vm: NotchViewModel

    var body: some View {
        IslandBody(vm: vm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
    }
}

/// The black island itself. Reads only layout inputs; content views observe their own data,
/// so a track change re-renders the player — not the island frame.
private struct IslandBody: View {
    let vm: NotchViewModel
    @State private var dropTargeted = false

    var body: some View {
        let size = vm.shapeSize
        let isOpen = vm.isOpen
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)

        ZStack(alignment: .top) {
            if isOpen {
                ExpandedView(vm: vm)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.islandReveal)
            } else {
                CompactView(vm: vm)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .background {
            // Fill, shadow and the island style's layers (Theme.swift).
            IslandBackdrop(shape: shape, isOpen: isOpen)
        }
        .overlay {
            // Edge light along the bottom when open — subtle depth, per island style.
            IslandRim(shape: shape, isOpen: isOpen)
        }
        .contentShape(shape)
        .onTapGesture {
            guard !vm.isOpen else { return }
            // Clicking a "Downloaded" activity puts the file straight on the shelf.
            if case .activity(.downloadFinished(_, let url)) = vm.compact {
                ShelfService.shared.add([url])
                DownloadsService.shared.clearRecent()
                vm.open(tab: .shelf)
            } else {
                vm.open()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadFileURLs(from: providers) { ShelfService.shared.add($0) }
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in vm.dropTargetChanged(targeted) }
        .animation(isOpen ? Motion.open : Motion.close, value: isOpen)
        .animation(Motion.compact, value: vm.compact.key)
        .animation(Motion.micro, value: vm.shapeSize.height) // command bar grows/shrinks with its results
        .animation(Motion.peek, value: vm.isHovering)
        .animation(Motion.compact, value: vm.geometry)
        .animation(Motion.open, value: vm.isCommandBarActive)
    }
}

func loadFileURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { MainActor.assumeIsolated { completion(urls) } }
}
