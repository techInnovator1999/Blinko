import SwiftUI

/// What the Appearance preview shows.
enum ThemePreviewMode: String, CaseIterable, Identifiable {
    case open, music, hud
    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: String(localized: "Open")
        case .music: String(localized: "Now Playing")
        case .hud: String(localized: "HUD")
        }
    }
}

/// The real island views (NotchRootView with its own view model) on a small desktop stage, so
/// every Appearance change shows instantly. It lives only while the Appearance pane is visible
/// and never touches the live islands' state.
struct ThemePreview: View {
    let mode: ThemePreviewMode
    var tab: NotchTab = .home
    /// Width of the stage on screen; the 900 pt "desktop" is scaled down to fit.
    var width: CGFloat = 500

    @State private var vm = ThemePreview.makeViewModel()

    static let desktop = CGSize(width: 900, height: 300)

    static func makeViewModel() -> NotchViewModel {
        let geometry = NSScreen.screens.first(where: \.hasNotch).map(NotchGeometry.make(for:))
            ?? NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                             notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        let vm = NotchViewModel(geometry: geometry)
        vm.isPreview = true
        return vm
    }

    var body: some View {
        let scale = width / Self.desktop.width
        ZStack(alignment: .top) {
            PreviewDesktop()
            NotchRootView(vm: vm)
                .frame(width: Self.desktop.width, height: Self.desktop.height)
                .allowsHitTesting(mode == .open)
        }
        .frame(width: Self.desktop.width, height: Self.desktop.height)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: width, height: Self.desktop.height * scale, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .onAppear(perform: sync)
        .onChange(of: mode) { _, _ in withAnimation(Motion.open) { sync() } }
        .onChange(of: tab) { _, _ in withAnimation(Motion.micro) { sync() } }
        // The header's gear / pin can close the preview island: reopen it.
        .onChange(of: vm.isOpen) { _, open in if !open, mode == .open { sync() } }
    }

    private func sync() {
        switch mode {
        case .open:
            vm.compactOverride = nil
            vm.open(tab: tab)
        case .music:
            vm.compactOverride = .music
            vm.close()
        case .hud:
            vm.compactOverride = .activity(.volume(level: 0.62, muted: false))
            vm.close()
        }
    }
}

/// The stage behind the preview island: the user's own desktop picture when it has been
/// sampled, otherwise a soft gradient, under a hint of a menu bar.
private struct PreviewDesktop: View {
    var body: some View {
        ZStack(alignment: .top) {
            if let wallpaper = Theme.shared.wallpaperThumbnail {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: ThemePreview.desktop.width, height: ThemePreview.desktop.height)
                    .clipped()
            } else {
                LinearGradient(colors: [Color(red: 0.25, green: 0.3, blue: 0.5), Color(red: 0.62, green: 0.45, blue: 0.58)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Rectangle().fill(.black.opacity(0.22)).frame(height: 32)
        }
    }
}
