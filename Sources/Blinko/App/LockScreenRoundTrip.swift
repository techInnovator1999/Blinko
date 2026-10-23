import AppKit
import SwiftUI

/// Hidden diagnostic: `open -n Blinko.app --args --lockscreen-roundtrip-test [report.txt]`.
///
/// Proves the lock-screen plumbing on the *unlocked* desktop without locking anything: it
/// resolves the private SkyLight symbols, shows a small test panel (configured exactly like
/// the island's `NotchPanel`) in the top-left corner, moves it into the lock-screen space for
/// ~2 s with the same code the lock-screen controller uses, restores it, and compares what
/// the window server reports (layer, on-screen, alpha, spaces) before / during / after.
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
        var description: String {
            "layer=\(layer.map(String.init) ?? "nil") onscreen=\(onscreen) alpha=\(alpha.map { String($0) } ?? "nil") "
                + "level=\(level) collectionBehavior=0x\(String(collection, radix: 16)) spaces=\(spaces.map { "\($0)" } ?? "n/a")"
        }
    }

    private static func sample(_ window: NSWindow) -> WindowSample {
        let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber)) as? [[String: Any]])?.first
        return WindowSample(layer: info?[kCGWindowLayer as String] as? Int,
                            onscreen: info?[kCGWindowIsOnscreen as String] as? Bool ?? false,
                            alpha: info?[kCGWindowAlpha as String] as? Double,
                            level: window.level.rawValue,
                            collection: window.collectionBehavior.rawValue,
                            spaces: SkyLightSpace.shared.spaces(of: window))
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

        // Same configuration as an island panel, tiny and in a corner.
        let panel = NotchPanel()
        let hosting = NSHostingView(rootView:
            Text(verbatim: "Blinko lock-screen test")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 180, height: 26)
                .background(Capsule().fill(Color.pink)))
        panel.contentView = hosting
        let screen = NSScreen.screens.first?.frame ?? .zero
        panel.setFrame(CGRect(x: screen.minX + 12, y: screen.maxY - 70, width: 180, height: 26), display: true)
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let before = sample(panel)
            lines.append("before:  \(before)")
            guard sky.show() else { lines.append("could not create / show the space"); finish(1) }
            lines.append("space id: \(sky.spaceID) (absolute level \(SkyLightSpace.lockScreenLevel))")
            let state = LockScreenController.capture(panel)
            let moved = LockScreenController.moveToLockSpace(panel)
            lines.append("moved into space: \(moved)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let during = sample(panel)
                lines.append("during:  \(during)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    LockScreenController.restore(panel, state, reorder: true)
                    sky.hide()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let after = sample(panel)
                        lines.append("after:   \(after)")
                        var ok = true
                        func check(_ cond: Bool, _ what: String) {
                            lines.append("\(cond ? "ok  " : "FAIL") \(what)")
                            ok = ok && cond
                        }
                        check(moved, "window accepted by SLSSpaceAddWindowsAndRemoveFromSpaces")
                        if let spaces = during.spaces { check(spaces.contains(sky.spaceID), "window in the lock-screen space while delegated") }
                        if let spaces = after.spaces { check(!spaces.contains(sky.spaceID), "window left the lock-screen space") }
                        if let b = before.spaces, let a = after.spaces { check(Set(a) == Set(b), "window back in its original spaces \(b)") }
                        check(after.onscreen, "window on screen after restore")
                        check(after.layer == before.layer, "window-server layer restored (\(before.layer ?? -1))")
                        check(after.level == before.level, "NSWindow level restored")
                        check(after.collection == before.collection, "collection behaviour restored")
                        check(panel.canBecomeVisibleWithoutLogin == state.canBecomeVisibleWithoutLogin, "canBecomeVisibleWithoutLogin restored")
                        panel.orderOut(nil)
                        finish(ok ? 0 : 1)
                    }
                }
            }
        }
    }
}
