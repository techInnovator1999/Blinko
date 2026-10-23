import AppKit
import Observation
import SwiftUI

// MARK: - Options (persisted in Preferences)

/// Where the app-wide accent colour comes from.
enum AccentPreset: String, CaseIterable, Identifiable, Codable {
    case blinko, violet, ocean, mint, sunset, mono, custom, album, wallpaper
    var id: String { rawValue }

    /// The fixed swatches, in picker order.
    static let swatches: [AccentPreset] = [.blinko, .violet, .ocean, .mint, .sunset, .mono]

    var title: String {
        switch self {
        case .blinko: String(localized: "Blinko Pink")
        case .violet: String(localized: "Violet")
        case .ocean: String(localized: "Ocean")
        case .mint: String(localized: "Mint")
        case .sunset: String(localized: "Sunset")
        case .mono: String(localized: "Mono")
        case .custom: String(localized: "Custom")
        case .album: String(localized: "Match album art")
        case .wallpaper: String(localized: "Match wallpaper")
        }
    }

    /// Fixed colour for the swatch presets (nil for the dynamic ones).
    var fixedColor: NSColor? {
        switch self {
        case .blinko: NSColor(srgbRed: 1.00, green: 0.36, blue: 0.58, alpha: 1)
        case .violet: NSColor(srgbRed: 0.67, green: 0.53, blue: 1.00, alpha: 1)
        case .ocean: NSColor(srgbRed: 0.25, green: 0.64, blue: 1.00, alpha: 1)
        case .mint: NSColor(srgbRed: 0.38, green: 0.90, blue: 0.71, alpha: 1)
        case .sunset: NSColor(srgbRed: 1.00, green: 0.56, blue: 0.27, alpha: 1)
        case .mono: NSColor(white: 0.96, alpha: 1)
        case .custom, .album, .wallpaper: nil
        }
    }
}

/// The open island's look. The closed island always stays pure black so it reads as the notch.
enum IslandStyle: String, CaseIterable, Identifiable, Codable {
    case classic, minimal, glass, glow
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: String(localized: "Classic")
        case .minimal: String(localized: "Minimal")
        case .glass: String(localized: "Glass")
        case .glow: String(localized: "Glow")
        }
    }

    var subtitle: String {
        switch self {
        case .classic: String(localized: "Pure black, one with the notch")
        case .minimal: String(localized: "Chrome appears on hover")
        case .glass: String(localized: "Frosted edge, soft inner light")
        case .glow: String(localized: "Accent glow beneath")
        }
    }
}

/// Open-island size. A preset is a width; height and content scale follow the width, so the
/// width slider in Layout keeps working and simply reads as "Custom" between presets.
enum SizePreset: String, CaseIterable, Identifiable, Codable {
    case compact, standard, large, custom
    var id: String { rawValue }

    static let choices: [SizePreset] = [.compact, .standard, .large]

    var title: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .standard: String(localized: "Default")
        case .large: String(localized: "Large")
        case .custom: String(localized: "Custom")
        }
    }

    var width: Double? {
        switch self {
        case .compact: 640
        case .standard: 700
        case .large: 780
        case .custom: nil
        }
    }

    init(width: Double) {
        self = SizePreset.choices.first { $0.width == width } ?? .custom
    }
}

enum FontStyle: String, CaseIterable, Identifiable, Codable {
    case system, rounded
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "SF Pro")
        case .rounded: String(localized: "SF Pro Rounded")
        }
    }
}

// MARK: - Theme

/// Derived look of the island: accent, radii, size, typography and style. Everything is a
/// cheap computed read over `Preferences`, so a view that reads `Theme.shared.accent` is
/// invalidated only by the inputs of that one value. The only work it does on its own is
/// sampling the desktop picture — off-main, and only on space / screen changes while
/// "Match wallpaper" is selected.
@MainActor
@Observable
final class Theme {
    static let shared = Theme()

    /// Dominant colour of the current desktop picture (nil until sampled, or if unreadable).
    private(set) var wallpaperColor: NSColor?
    /// Small copy of the desktop picture for the Appearance preview stage.
    private(set) var wallpaperThumbnail: NSImage?

    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sampling = false

    private init() {}

    // MARK: Accent

    var accentNSColor: NSColor {
        switch prefs.accentPreset {
        case .custom:
            return PickedColor(hex: prefs.customAccentHex)?.nsColor ?? AccentPreset.blinko.fixedColor!
        case .album:
            let np = NowPlayingService.shared
            return np.hasTrack ? np.accent : AccentPreset.blinko.fixedColor!
        case .wallpaper:
            return wallpaperColor ?? AccentPreset.blinko.fixedColor!
        default:
            return prefs.accentPreset.fixedColor ?? AccentPreset.blinko.fixedColor!
        }
    }

    var accent: Color { Color(nsColor: accentNSColor) }

    /// Foreground for text / symbols drawn on a solid accent fill (selected tab pill).
    var onAccent: Color {
        guard let c = accentNSColor.usingColorSpace(.sRGB) else { return .black }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.55 ? .black : .white
    }

    // MARK: Style

    var style: IslandStyle { prefs.islandStyle }

    // MARK: Size

    var sizePreset: SizePreset { SizePreset(width: prefs.openWidth) }

    /// Content scale follows the open width: 640 → 0.92, 700 → 1, 780 → 1.08 (clamped),
    /// so the tab layouts always see roughly the 700 pt design width.
    private var widthScale: CGFloat {
        let w = CGFloat(prefs.openWidth)
        let s = w < 700 ? 1 - (700 - w) / 60 * 0.08 : 1 + (w - 700) / 80 * 0.08
        return min(max(s, 0.9), 1.1)
    }

    /// Scale applied to the open island's tab content (not to the header, which lines up
    /// with the notch at true size). Minimal draws slightly smaller type.
    var contentScale: CGFloat { widthScale * (style == .minimal ? 0.95 : 1) }

    var openHeight: CGFloat { (Metrics.openSize.height * widthScale).rounded() }

    /// Room around the open island for its shadow / glow (window size; never hover-dependent).
    var shadowPadding: CGFloat { style == .glow ? 40 : Metrics.shadowPadding }

    // MARK: Corners

    var openTopRadius: CGFloat { style == .minimal ? Metrics.openTopRadius - 3 : Metrics.openTopRadius }

    var openBottomRadius: CGFloat {
        CGFloat(prefs.openCornerRadius) - (style == .minimal ? 6 : 0)
    }

    var closedBottomRadius: CGFloat { CGFloat(prefs.closedCornerRadius) }

    // MARK: Typography

    var fontDesign: Font.Design { prefs.fontStyle == .rounded ? .rounded : .default }

    /// Numbers and titles (clock, timers, stats, player title) in the chosen design.
    func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: fontDesign)
    }

    // MARK: Wallpaper

    /// Follows the accent preset: the wallpaper is sampled (and space / screen changes are
    /// observed) only while "Match wallpaper" is selected.
    func start() {
        withObservationTracking {
            _ = prefs.accentPreset
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.start() }
        }
        if prefs.accentPreset == .wallpaper {
            if observers.isEmpty { observeDesktopChanges() }
            if wallpaperColor == nil { refreshWallpaper() }
        } else if !observers.isEmpty {
            observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
            observers = []
        }
    }

    private func observeDesktopChanges() {
        let refresh: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { Theme.shared.refreshWallpaper() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: refresh))
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: refresh))
    }

    /// Samples the desktop picture of the main screen once, off the main thread.
    func refreshWallpaper() {
        guard !sampling else { return }
        let screen = NSScreen.screens.first { $0.hasNotch } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        sampling = true
        Task.detached(priority: .utility) {
            let sample = WallpaperSampler.sample(url)
            await MainActor.run {
                let theme = Theme.shared
                theme.sampling = false
                if theme.wallpaperColor != sample?.color { theme.wallpaperColor = sample?.color }
                theme.wallpaperThumbnail = sample?.thumbnail
            }
        }
    }

    // MARK: Reset

    func resetToDefaults() {
        prefs.accentPreset = .blinko
        prefs.customAccentHex = "#FF5C94"
        prefs.islandStyle = .classic
        prefs.openWidth = 700
        prefs.openCornerRadius = Double(Metrics.openBottomRadius)
        prefs.closedCornerRadius = Double(Metrics.closedBottomRadius)
        prefs.fontStyle = .system
    }
}

// MARK: - Wallpaper sampling

/// Reads a desktop picture through ImageIO thumbnails (never the full-size bitmap) and
/// finds its dominant hue, lifted so it reads on pure black.
enum WallpaperSampler {
    struct Sample: @unchecked Sendable {
        let color: NSColor
        let thumbnail: NSImage?
    }

    nonisolated static func sample(_ url: URL) -> Sample? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        func thumb(_ px: Int) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(source, index, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: px,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ] as CFDictionary)
        }
        guard let small = thumb(48), let color = dominantColor(small) else { return nil }
        let preview = thumb(480).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        return Sample(color: color, thumbnail: preview)
    }

    /// Hue histogram weighted by saturation × brightness; the heaviest bucket wins.
    nonisolated static func dominantColor(_ image: CGImage) -> NSColor? {
        let w = 32, h = 32
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let buckets = 18
        var weight = [Double](repeating: 0, count: buckets)
        var sums = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: buckets)
        var total = (r: 0.0, g: 0.0, b: 0.0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            total.r += r; total.g += g; total.b += b
            let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
            guard maxV > 0.12, delta > 0.06 else { continue }
            var hue: Double
            switch maxV {
            case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            hue = hue / 6; if hue < 0 { hue += 1 }
            let k = min(Int(hue * Double(buckets)), buckets - 1)
            let wgt = (delta / maxV) * maxV
            weight[k] += wgt
            sums[k].r += r * wgt; sums[k].g += g * wgt; sums[k].b += b * wgt
        }
        let base: NSColor
        if let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 4 {
            let s = sums[best], wgt = weight[best]
            base = NSColor(srgbRed: s.r / wgt, green: s.g / wgt, blue: s.b / wgt, alpha: 1)
        } else {
            let n = Double(w * h)
            base = NSColor(srgbRed: total.r / n, green: total.g / n, blue: total.b / n, alpha: 1)
        }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        if sat < 0.12 { return NSColor(white: 0.92, alpha: 1) } // monochrome wallpaper: stay neutral
        return NSColor(hue: hue, saturation: min(max(sat * 1.1, 0.35), 0.8), brightness: max(bri, 0.85), alpha: 1)
    }
}
