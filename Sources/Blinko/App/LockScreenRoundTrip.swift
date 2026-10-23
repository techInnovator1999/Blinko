import AppKit
import SwiftUI

/// Hidden diagnostic: `open -n Blinko.app --args --lockscreen-roundtrip-test [report.txt]`.
///
/// Proves the lock-screen plumbing on the *unlocked* desktop without locking anything: it
/// resolves the private SkyLight symbols, shows two small test panels in the top-left corner
/// — one configured exactly like the island's `NotchPanel`, one at the normal window level —
/// moves both into the lock-screen space for ~2 s with the code the lock-screen controller
/// uses, restores them, and compares what the window server reports before / during / after:
/// layer, on-screen, alpha, z-order and spaces. The normal-level panel jumping in front of
/// higher-layer windows (menu bar, Dock…) shows the space's absolute level is in effect.
/// Writes a report and exits 0 on success, 1 on a mismatch, 2 if SkyLight is unavailable.
@MainActor
enum LockScreenRoundTrip {
    static func runIfRequested(_ app: NSApplication) -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--lockscreen-roundtrip-test") else { return false }
        let path = i + 1 < args.count && !args[i + 1].hasPrefix("--")
            ? args[i + 1] : NSTemporaryDirectory() + "blinko-lockscreen-roundtrip.txt"
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async { run(report: URL(fileURLWithPath: path)) }
        app.run()
        return true
    }

    private struct WindowSample: CustomStringConvertible {
        var layer: Int?
        var onscreen: Bool
        var alpha: Double?
        var level: Int
        var collection: UInt
        var spaces: [UInt64]?
        /// Position in the front-to-back list of on-screen windows.
        var zIndex: Int?
        /// On-screen windows with a higher layer drawn in front of this one.
        var higherLayersInFront: Int
        /// Owner:layer of every window in front (front to back).
        var inFront: [String] = []

        var description: String {
            "layer=\(layer.map(String.init) ?? "nil") onscreen=\(onscreen) alpha=\(alpha.map { String($0) } ?? "nil") "
                + "level=\(level) collectionBehavior=0x\(String(collection, radix: 16)) "
                + "z=\(zIndex.map(String.init) ?? "nil") higherLayersInFront=\(higherLayersInFront) "
                + "spaces=\(spaces.map { "\($0)" } ?? "n/a")"
                + " inFront=\(inFront)"
        }
    }

    private static func sample(_ window: NSWindow) -> WindowSample {
        let number = window.windowNumber
        let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(number)) as? [[String: Any]])?.first
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let z = list.firstIndex { ($0[kCGWindowNumber as String] as? Int) == number }
        let layer = info?[kCGWindowLayer as String] as? Int
        let higher = z.map { idx in
            list[..<idx].filter { ($0[kCGWindowLayer as String] as? Int ?? 0) > (layer ?? 0) }.count
        } ?? 0
        return WindowSample(layer: layer,
                            onscreen: info?[kCGWindowIsOnscreen as String] as? Bool ?? false,
                            alpha: info?[kCGWindowAlpha as String] as? Double,
                            level: window.level.rawValue,
                            collection: window.collectionBehavior.rawValue,
                            spaces: SkyLightSpace.shared.spaces(of: window),
                            zIndex: z, higherLayersInFront: higher,
                            inFront: z.map { list[..<$0].map { "\($0[kCGWindowOwnerName as String] as? String ?? "?"):\($0[kCGWindowLayer as String] as? Int ?? 0)" } } ?? [])
    }

    private static func makePanel(_ title: String, color: Color, y: CGFloat, level: NSWindow.Level?) -> NotchPanel {
        let panel = NotchPanel()
        if let level { panel.level = level }
        panel.contentView = NSHostingView(rootView:
            Text(verbatim: title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 180, height: 26)
                .background(Capsule().fill(color)))
        let screen = NSScreen.screens.first?.frame ?? .zero
        panel.setFrame(CGRect(x: screen.minX + 12, y: screen.maxY - y, width: 180, height: 26), display: true)
        panel.orderFrontRegardless()
        return panel
    }

    private static func run(report: URL) {
        var lines: [String] = ["Blinko lock-screen round-trip test — \(Date())",
                               "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        func finish(_ code: Int32) -> Never {
            lines.append(code == 0 ? "RESULT: PASS" : "RESULT: FAIL (\(code))")
            try? lines.joined(separator: "\n").appending("\n").write(to: report, atomically: true, encoding: .utf8)
            SkyLightSpace.shared.destroy()
            exit(code)
        }

        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY | RTLD_LOCAL)
        for name in SkyLightSpace.requiredSymbols + SkyLightSpace.optionalSymbols {
            let required = SkyLightSpace.requiredSymbols.contains(name)
            lines.append("symbol \(name): \(dlsym(handle, name) != nil ? "resolved" : "MISSING")\(required ? "" : " (optional)")")
        }
        let sky = SkyLightSpace.shared
        guard sky.isAvailable else { lines.append("SkyLight unavailable"); finish(2) }

        let panels: [(name: String, panel: NotchPanel)] = [
            ("island-like panel", makePanel("Blinko lock-screen test", color: .pink, y: 70, level: nil)),
            ("normal-level panel", makePanel("Blinko lock-screen test 2", color: .indigo, y: 104, level: .normal)),
        ]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let before = panels.map { sample($0.panel) }
            guard sky.show() else { lines.append("could not create / show the space"); finish(1) }
            lines.append("space id: \(sky.spaceID) (absolute level \(SkyLightSpace.lockScreenLevel))")
            let states = panels.map { LockScreenController.capture($0.panel) }
            panels.forEach { LockScreenController.moveToLockSpace($0.panel) }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let during = panels.map { sample($0.panel) }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    for (entry, state) in zip(panels, states) {
                        LockScreenController.restore(entry.panel, state, reorder: true)
                    }
                    sky.hide()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        var ok = true
                        func check(_ cond: Bool, _ what: String) {
                            lines.append("  \(cond ? "ok  " : "FAIL") \(what)")
                            ok = ok && cond
                        }
                        for (i, entry) in panels.enumerated() {
                            let (b, d, a, state) = (before[i], during[i], sample(entry.panel), states[i])
                            lines.append("\(entry.name):")
                            lines.append("  before: \(b)")
                            lines.append("  during: \(d)")
                            lines.append("  after:  \(a)")
                            if let spaces = d.spaces { check(spaces == [sky.spaceID], "only in the lock-screen space while delegated") }
                            check(d.onscreen, "on screen while delegated")
                            // Only the other test panel (same space, higher layer) and window-server
                            // overlays (cursor, screen shields: their own top spaces) may be in front;
                            // the space's absolute level lifts it above the menu bar, Dock and every
                            // app window whatever their layer.
                            let foreign = d.inFront.filter { !$0.hasPrefix("Blinko:") && !$0.hasPrefix("Window Server:2147") }
                            let lifted = b.inFront.filter { !$0.hasPrefix("Blinko:") && !$0.hasPrefix("Window Server:2147") }
                            check(foreign.isEmpty, "drawn above \(lifted) while delegated")
                            if let s = a.spaces { check(!s.contains(sky.spaceID), "left the lock-screen space") }
                            if let bs = b.spaces, let s = a.spaces { check(Set(s) == Set(bs), "back in its original \(bs.count) space(s)") }
                            check(a.onscreen, "on screen after restore")
                            check(a.layer == b.layer, "window-server layer restored (\(b.layer ?? -1))")
                            check(a.alpha == b.alpha, "alpha restored")
                            check(a.level == b.level, "NSWindow level restored")
                            check(a.collection == b.collection, "collection behaviour restored")
                            // Back under the system overlays it was under before (the Dock may come
                            // and go on its own, so compare the front-most system window only).
                            if let top = b.inFront.first(where: { !$0.hasPrefix("Blinko:") }) {
                                check(a.inFront.contains(top), "back below \(top) as before")
                            }
                            check(entry.panel.canBecomeVisibleWithoutLogin == state.canBecomeVisibleWithoutLogin,
                                  "canBecomeVisibleWithoutLogin restored")
                        }
                        panels.forEach { $0.panel.orderOut(nil) }
                        finish(ok ? 0 : 1)
                    }
                }
            }
        }
    }
}
