import AppKit
import SwiftUI

/// `Blinko --snapshot <dir>` renders every island state to PNG for design review,
/// without starting services or touching the menu bar.
@MainActor
enum Snapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        render(to: dir)
        return true
    }

    private static func render(to dir: URL) {
        let geometry = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                     notchSize: CGSize(width: 185, height: 32), hasNotch: true)
        NowPlayingService.shared.injectPreview(title: "Midnight City", artist: "M83",
                                               duration: 243, elapsed: 97, playing: true,
                                               artwork: sampleArtwork())

        func shot(_ name: String, setup: (NotchViewModel) -> Void) {
            let vm = NotchViewModel(geometry: geometry)
            setup(vm)
            let canvas = CGSize(width: 760, height: 280)
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.75, green: 0.55, blue: 0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                NotchRootView(vm: vm).frame(width: canvas.width, height: canvas.height)
            }
            .frame(width: canvas.width, height: canvas.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage else { return }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        }

        shot("01-closed-music") { _ in }
        shot("02-hud-volume") { _ in ActivityCenter.shared.show(.volume(level: 0.62, muted: false)) }
        shot("03-charging") { _ in ActivityCenter.shared.show(.power(level: 76, charging: true, pluggedIn: true)) }
        shot("04-bluetooth") { _ in ActivityCenter.shared.show(.bluetooth(name: "AirPods Pro", kind: .headphones, connected: true)) }
        shot("05-capslock") { _ in ActivityCenter.shared.show(.capsLock(on: true)) }
        shot("06-mic") { _ in ActivityCenter.shared.show(.microphone(level: 0.4, muted: false)) }
        shot("07-focus") { _ in ActivityCenter.shared.show(.focusSession(title: "Short Break", isBreak: true)) }
        // v0.3 awareness activities
        let airpods = DeviceBattery(left: 82, right: 76, caseLevel: 54)
        shot("11-airpods-battery") { _ in ActivityCenter.shared.show(.bluetooth(name: "AirPods Pro", kind: .headphones, connected: true, battery: airpods)) }
        shot("12-focus-mode") { _ in ActivityCenter.shared.show(.focusMode(on: true, name: "Do Not Disturb", symbol: "moon.fill")) }
        shot("12b-focus-off") { _ in ActivityCenter.shared.show(.focusMode(on: false, name: nil, symbol: nil)) }
        shot("13-privacy-camera") { _ in ActivityCenter.shared.show(.privacy(sensor: .camera)) }
        shot("14-wifi") { _ in ActivityCenter.shared.show(.network(.wifi(connected: true, ssid: "Studio 5G"))) }
        shot("14b-vpn") { _ in ActivityCenter.shared.show(.network(.vpn(on: true))) }
        shot("14c-hotspot") { _ in ActivityCenter.shared.show(.network(.hotspot(name: "iPhone"))) }
        let downloaded = URL(fileURLWithPath: "/tmp/Blinko-0.3.0.dmg")
        shot("15-download-finished") { _ in ActivityCenter.shared.show(.downloadFinished(name: downloaded.lastPathComponent, url: downloaded)) }
        ActivityCenter.shared.dismiss()
        PrivacyService.shared.injectPreview(camera: true, mic: true)
        shot("16-privacy-over-music") { _ in }
        DownloadsService.shared.injectPreview(.init(name: "Xcode.xip", received: 1_200_000_000, total: 3_000_000_000), count: 2)
        shot("17-download-progress") { _ in }
        DownloadsService.shared.injectPreview(.init(name: "video.mp4", received: 48_500_000, total: nil))
        shot("17b-download-indeterminate") { _ in }
        DownloadsService.shared.injectPreview(nil, recent: downloaded)
        let idleClock = Preferences.shared.showClockWhenIdle
        let np = NowPlayingService.shared
        np.injectPreview(title: np.title, artist: np.artist, duration: np.duration, elapsed: 97, playing: false, artwork: np.artwork)
        shot("16b-privacy-idle") { _ in }
        PrivacyService.shared.injectPreview(camera: false, mic: false)
        Preferences.shared.showClockWhenIdle = true
        shot("09-idle-clock") { _ in }
        Preferences.shared.showClockWhenIdle = idleClock
        np.injectPreview(title: np.title, artist: np.artist, duration: np.duration, elapsed: 97, playing: true, artwork: np.artwork)
        TimerService.shared.startFocus()
        shot("08-compact-focus") { _ in }
        for tab in NotchTab.allCases {
            shot("10-open-\(tab.rawValue)") { vm in vm.open(tab: tab) }
        }
    }

    private static func sampleArtwork() -> NSImage {
        let size = NSSize(width: 256, height: 256)
        return NSImage(size: size, flipped: false) { rect in
            let g = NSGradient(colors: [NSColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1),
                                        NSColor(red: 0.35, green: 0.2, blue: 0.75, alpha: 1)])
            g?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 80, dy: 80)).fill()
            return true
        }
    }
}
