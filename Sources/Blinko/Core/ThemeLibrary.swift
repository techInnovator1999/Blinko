import AppKit
import UniformTypeIdentifiers

/// A complete island look as a small JSON document: built-in themes, export and import.
/// Unknown or missing keys fall back to the defaults, so files stay readable across versions.
struct ThemeFile: Codable, Equatable {
    var name: String
    var accent: AccentPreset
    var customAccent: String
    var style: IslandStyle
    var openWidth: Double
    var openCornerRadius: Double
    var closedCornerRadius: Double
    var font: FontStyle

    static let format = "blinko-theme"

    init(name: String, accent: AccentPreset, customAccent: String = "#FF5C94", style: IslandStyle,
         openWidth: Double = 700, openCornerRadius: Double = 26, closedCornerRadius: Double = 14,
         font: FontStyle = .system) {
        self.name = name; self.accent = accent; self.customAccent = customAccent; self.style = style
        self.openWidth = openWidth; self.openCornerRadius = openCornerRadius
        self.closedCornerRadius = closedCornerRadius; self.font = font
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, name, accent, customAccent, style, openWidth, openCornerRadius, closedCornerRadius, font
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let format = try c.decodeIfPresent(String.self, forKey: .format), format != Self.format {
            throw CocoaError(.fileReadCorruptFile)
        }
        let d = ThemeFile.defaults
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? String(localized: "Imported Theme")
        accent = (try? c.decodeIfPresent(AccentPreset.self, forKey: .accent)) ?? d.accent
        customAccent = (try? c.decodeIfPresent(String.self, forKey: .customAccent))
            .flatMap { PickedColor(hex: $0)?.hex } ?? d.customAccent
        style = (try? c.decodeIfPresent(IslandStyle.self, forKey: .style)) ?? d.style
        openWidth = Self.clamp(try? c.decodeIfPresent(Double.self, forKey: .openWidth), 600...840, d.openWidth)
        openCornerRadius = Self.clamp(try? c.decodeIfPresent(Double.self, forKey: .openCornerRadius),
                                      ThemeFile.openRadiusRange, d.openCornerRadius)
        closedCornerRadius = Self.clamp(try? c.decodeIfPresent(Double.self, forKey: .closedCornerRadius),
                                        ThemeFile.closedRadiusRange, d.closedCornerRadius)
        font = (try? c.decodeIfPresent(FontStyle.self, forKey: .font)) ?? d.font
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.format, forKey: .format)
        try c.encode(1, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encode(accent, forKey: .accent)
        try c.encode(customAccent, forKey: .customAccent)
        try c.encode(style, forKey: .style)
        try c.encode(openWidth, forKey: .openWidth)
        try c.encode(openCornerRadius, forKey: .openCornerRadius)
        try c.encode(closedCornerRadius, forKey: .closedCornerRadius)
        try c.encode(font, forKey: .font)
    }

    private static func clamp(_ value: Double?, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        guard let v = value, v.isFinite else { return fallback }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    static let openRadiusRange: ClosedRange<Double> = 16...36
    static let closedRadiusRange: ClosedRange<Double> = 8...20

    /// Same look, ignoring the name.
    func matches(_ other: ThemeFile) -> Bool {
        var a = self, b = other
        a.name = ""; b.name = ""
        if a.accent != .custom { a.customAccent = ""; }
        if b.accent != .custom { b.customAccent = ""; }
        return a == b
    }

    // MARK: Built-ins

    static let defaults = ThemeFile(name: "Blinko", accent: .blinko, style: .classic)

    static let builtIns: [ThemeFile] = [
        ThemeFile(name: "Midnight", accent: .custom, customAccent: "#6F8CFF", style: .classic,
                  openCornerRadius: 24, closedCornerRadius: 13),
        ThemeFile(name: "Aurora", accent: .custom, customAccent: "#5EF0C4", style: .glass,
                  openCornerRadius: 30, closedCornerRadius: 15, font: .rounded),
        ThemeFile(name: "Paper", accent: .mono, style: .minimal, openWidth: 640,
                  openCornerRadius: 22, closedCornerRadius: 12),
        ThemeFile(name: "Neon", accent: .custom, customAccent: "#FF3DD8", style: .glow,
                  openCornerRadius: 28, closedCornerRadius: 14, font: .rounded),
    ]
}

@MainActor
enum ThemeLibrary {
    static var current: ThemeFile {
        let p = Preferences.shared
        return ThemeFile(name: String(localized: "My Blinko Theme"), accent: p.accentPreset, customAccent: p.customAccentHex,
                         style: p.islandStyle, openWidth: p.openWidth, openCornerRadius: p.openCornerRadius,
                         closedCornerRadius: p.closedCornerRadius, font: p.fontStyle)
    }

    static func apply(_ theme: ThemeFile) {
        let p = Preferences.shared
        p.accentPreset = theme.accent
        p.customAccentHex = theme.customAccent
        p.islandStyle = theme.style
        p.openWidth = theme.openWidth
        p.openCornerRadius = theme.openCornerRadius
        p.closedCornerRadius = theme.closedCornerRadius
        p.fontStyle = theme.font
    }

    static func encode(_ theme: ThemeFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(theme)
    }

    static func decode(_ data: Data) throws -> ThemeFile {
        try JSONDecoder().decode(ThemeFile.self, from: data)
    }

    /// Save panel → JSON file.
    static func exportCurrent() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "Blinko Theme") + ".json"
        panel.title = String(localized: "Export Theme")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var theme = current
        theme.name = url.deletingPathExtension().lastPathComponent
        do {
            try encode(theme).write(to: url, options: .atomic)
        } catch {
            alert(String(localized: "Couldn't export the theme."), error.localizedDescription)
        }
    }

    /// Open panel → applies the theme. Returns its name.
    @discardableResult
    static func importTheme() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "Import Theme")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard data.count < 64_000 else { throw CocoaError(.fileReadTooLarge) }
            let theme = try decode(data)
            apply(theme)
            return theme.name
        } catch {
            alert(String(localized: "This file isn't a Blinko theme."),
                  String(localized: "Choose a .json file exported from Blinko's Appearance settings."))
            return nil
        }
    }

    private static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
