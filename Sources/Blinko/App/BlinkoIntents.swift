import AppIntents
import Foundation

// Native Shortcuts actions. Each one goes through the same code path as the blinko:// URL
// scheme and the `blinko` CLI. The metadata Shortcuts reads (Contents/Resources/Metadata.appintents)
// is produced by scripts/build.sh with `appintentsmetadataprocessor`; without it these types are inert.

@MainActor
private func run(_ action: String, _ items: [(String, String?)] = []) throws {
    var c = URLComponents()
    c.scheme = "blinko"
    let parts = action.split(separator: "/", maxSplits: 1).map(String.init)
    c.host = parts.first
    if parts.count > 1 { c.path = "/" + parts[1] }
    let query = items.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    if !query.isEmpty { c.queryItems = query }
    guard let url = c.url, URLSchemeHandler.perform(url) else {
        throw BlinkoIntentError.failed
    }
}

enum BlinkoIntentError: Error, CustomLocalizedStringResourceConvertible {
    case failed
    var localizedStringResource: LocalizedStringResource { "Blinko couldn't do that." }
}

struct ShowAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Alert in Island"
    static let description = IntentDescription("Shows a short custom activity in Blinko's island.")

    @Parameter(title: "Title") var title: String
    @Parameter(title: "Subtitle") var body: String?
    @Parameter(title: "SF Symbol", default: "bell.fill") var symbol: String?
    @Parameter(title: "Colour", description: "A colour name (orange, green…) or #RRGGBB.", default: "orange") var color: String?
    @Parameter(title: "Seconds", default: 4, inclusiveRange: (1, 30)) var duration: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$title) in the island") {
            \.$body
            \.$symbol
            \.$color
            \.$duration
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try run("alert", [("title", title), ("body", body), ("icon", symbol), ("color", color), ("duration", String(duration))])
        return .result()
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Timer"
    static let description = IntentDescription("Starts a countdown in Blinko.")

    @Parameter(title: "Minutes", default: 5, inclusiveRange: (1, 1440)) var minutes: Int
    @Parameter(title: "Label") var label: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer") { \.$label }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try run("timer", [("minutes", String(minutes)), ("label", label)])
        return .result()
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Session"
    static let description = IntentDescription("Starts a Pomodoro focus session in Blinko.")

    @MainActor
    func perform() async throws -> some IntentResult {
        try run("focus/start")
        return .result()
    }
}

enum IslandTabOption: String, AppEnum {
    case home, shelf, clipboard, stats, timer, notes, tools, agents

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Island Tab"
    static let caseDisplayRepresentations: [IslandTabOption: DisplayRepresentation] = [
        .home: "Home", .shelf: "Shelf", .clipboard: "Clipboard", .stats: "System", .timer: "Timer",
        .notes: "Notes", .tools: "Tools", .agents: "Agents",
    ]
}

struct OpenIslandIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Island"
    static let description = IntentDescription("Opens Blinko's island, optionally on a tab.")

    @Parameter(title: "Tab") var tab: IslandTabOption?

    static var parameterSummary: some ParameterSummary { Summary("Open the island on \(\.$tab)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        try run("open", [("tab", tab?.rawValue)])
        return .result()
    }
}

struct AddToShelfIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Shelf"
    static let description = IntentDescription("Puts files on Blinko's shelf.")

    @Parameter(title: "Files") var files: [IntentFile]

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$files) to the shelf") }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Only files that exist on disk (not in-memory data) can live on the shelf.
        let paths = files.compactMap { $0.fileURL?.path }
        guard !paths.isEmpty else { throw BlinkoIntentError.failed }
        try run("shelf/add", paths.map { ("path", $0) })
        return .result()
    }
}

struct KeepAwakeIntent: AppIntent {
    static let title: LocalizedStringResource = "Keep Mac Awake"
    static let description = IntentDescription("Keeps the display awake for a while (0 minutes = until turned off), or turns it off.")

    @Parameter(title: "Turn On", default: true) var on: Bool
    @Parameter(title: "Minutes", default: 60, inclusiveRange: (0, 1440)) var minutes: Int

    static var parameterSummary: some ParameterSummary {
        When(\.$on, .equalTo, true) {
            Summary("Keep awake: \(\.$on) for \(\.$minutes) minutes")
        } otherwise: {
            Summary("Keep awake: \(\.$on)")
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if !on {
            try run("keepawake", [("off", "1")])
        } else {
            try run("keepawake", [("minutes", minutes > 0 ? String(minutes) : nil)])
        }
        return .result()
    }
}

struct BlinkoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(), phrases: ["Start a focus session in \(.applicationName)"],
                    shortTitle: "Start Focus", systemImageName: "brain.head.profile")
        AppShortcut(intent: OpenIslandIntent(), phrases: ["Open \(.applicationName)"],
                    shortTitle: "Open Island", systemImageName: "capsule.fill")
    }
}
