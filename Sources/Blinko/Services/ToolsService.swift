import AppKit
import IOKit.pwr_mgt
import Observation

/// Screen colour picker built on `NSColorSampler` (no permission needed). The last eight
/// colours are kept in UserDefaults as hex strings.
@MainActor
@Observable
final class ColorPickerService {
    static let shared = ColorPickerService()

    private(set) var current: PickedColor?
    private(set) var history: [PickedColor]
    private(set) var isSampling = false

    @ObservationIgnored private let key = "colorHistory"
    @ObservationIgnored private var sampler: NSColorSampler?

    private init() {
        history = (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(PickedColor.init(hex:))
        current = history.first
    }

    func pick(completion: @escaping () -> Void = {}) {
        guard !isSampling else { return }
        isSampling = true
        let s = NSColorSampler()
        sampler = s
        s.show { [weak self] color in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSampling = false
                self.sampler = nil
                if let color, let picked = PickedColor(color) { self.remember(picked) }
                completion()
            }
        }
    }

    func select(_ color: PickedColor) { current = color }

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func remember(_ color: PickedColor) {
        current = color
        history.removeAll { $0 == color }
        history.insert(color, at: 0)
        history = Array(history.prefix(8))
        UserDefaults.standard.set(history.map(\.hex), forKey: key)
    }

    /// Design-time data for snapshot rendering (not saved).
    func injectPreview(_ hexes: [String]) {
        history = hexes.compactMap(PickedColor.init(hex:))
        current = history.first
    }
}

/// An sRGB colour with the three text formats the picker offers.
struct PickedColor: Equatable, Hashable {
    let red: Int, green: Int, blue: Int

    init?(_ color: NSColor) {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        red = byte(c.redComponent); green = byte(c.greenComponent); blue = byte(c.blueComponent)
    }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        red = (v >> 16) & 0xFF; green = (v >> 8) & 0xFF; blue = v & 0xFF
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var rgb: String { "\(red), \(green), \(blue)" }

    var hsl: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
        let l = (maxV + minV) / 2
        var h = 0.0, s = 0.0
        if delta > 0 {
            s = delta / (1 - abs(2 * l - 1))
            switch maxV {
            case r: h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: h = 60 * ((b - r) / delta + 2)
            default: h = 60 * ((r - g) / delta + 4)
            }
            if h < 0 { h += 360 }
        }
        return "\(Int(h.rounded()))°, \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%"
    }
}

/// Keep Awake ("caffeinate"): an IOPM assertion that prevents idle display sleep, for a
/// fixed time or indefinitely. One work item ends a timed session; the assertion is
/// released on stop and when Blinko quits.
@MainActor
@Observable
final class KeepAwakeService {
    static let shared = KeepAwakeService()

    private(set) var isActive = false
    /// End of a timed session; nil while active means "indefinitely".
    private(set) var until: Date?

    @ObservationIgnored private var assertion = IOPMAssertionID(0)
    @ObservationIgnored private var expiry: DispatchWorkItem?

    func start(for duration: TimeInterval?) {
        stop()
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Blinko Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else { return }
        assertion = id
        isActive = true
        until = duration.map { Date().addingTimeInterval($0) }
        if let duration {
            let work = DispatchWorkItem { [weak self] in self?.stop() }
            expiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func stop() {
        expiry?.cancel()
        expiry = nil
        if isActive { IOPMAssertionRelease(assertion) }
        assertion = 0
        isActive = false
        until = nil
    }

    /// Design-time state for snapshot rendering (no assertion is taken).
    func injectPreview(until: Date?) {
        isActive = true
        self.until = until
    }
}
