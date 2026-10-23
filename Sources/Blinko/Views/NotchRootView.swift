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
            shape
                .fill(Color.notchBackground)
                .shadow(color: .black.opacity(isOpen && Preferences.shared.openShadow ? 0.6 : 0),
                        radius: isOpen ? 18 : 0, y: isOpen ? 8 : 0)
        }
        .overlay {
            // Hairline that catches light along the bottom edge when open — subtle depth.
            shape
                .stroke(LinearGradient(colors: [.clear, .white.opacity(isOpen ? 0.07 : 0)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onTapGesture {
            if !vm.isOpen { vm.open() }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadFileURLs(from: providers) { ShelfService.shared.add($0) }
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in vm.dropTargetChanged(targeted) }
        .animation(isOpen ? Motion.open : Motion.close, value: isOpen)
        .animation(Motion.compact, value: vm.compact.key)
        .animation(Motion.peek, value: vm.isHovering)
        .animation(Motion.compact, value: vm.geometry)
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
