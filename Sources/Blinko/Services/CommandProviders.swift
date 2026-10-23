import AppKit
import Observation
import SwiftUI

// MARK: - Results

enum CommandIcon {
    case symbol(String, Color)
    case file(URL)
    case image(NSImage)
}

struct CommandItem: Identifiable {
    enum Kind {
        case calculator, conversion, currency, action, app, shortcut, shelf, clipboard, web, placeholder

        var label: String {
            switch self {
            case .calculator: String(localized: "Calculator")
            case .conversion: String(localized: "Convert")
            case .currency: String(localized: "Currency")
            case .action: String(localized: "Blinko")
            case .app: String(localized: "Application")
            case .shortcut: String(localized: "Shortcut")
            case .shelf: String(localized: "Shelf")
            case .clipboard: String(localized: "Clipboard")
            case .web: String(localized: "Web")
            case .placeholder: ""
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    var subtitle: String = ""
    let icon: CommandIcon
    var score: Double = 0
    /// Verb shown on the selected row ("Open", "Copy", "Run").
    var verb: String = String(localized: "Open")
    let run: @MainActor () -> Void
    /// ⌘↩ (shelf: reveal in Finder; apps: show in Finder).
    var alternate: (@MainActor () -> Void)?
}

// MARK: - Model

/// State of the command bar. Providers are cheap in-memory filters; the expensive indexes
/// (apps, Shortcuts) are built lazily on first open off the main thread, currency rates are
/// fetched only when a currency query is typed. Nothing runs while the bar is closed.
@MainActor
@Observable
final class CommandBarModel {
    static let shared = CommandBarModel()
    static let maxResults = 6

    var query = "" { didSet { if query != oldValue { update() } } }
    private(set) var results: [CommandItem] = []
    var selection = 0
    /// Snapshot rendering draws the query as text (ImageRenderer can't draw a live TextField).
    private(set) var isPreview = false

    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onShowTab: ((NotchTab) -> Void)?

    /// Called when the bar opens: fresh query, indexes warmed up in the background.
    func prepare() {
        guard !isPreview else { return }
        query = ""
        selection = 0
        update()
        AppIndex.shared.loadIfNeeded { [weak self] in self?.update() }
        ShortcutsIndex.shared.loadIfNeeded { [weak self] in self?.update() }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func execute(alternate: Bool = false) {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        guard item.kind != .placeholder else { return }
        let action = alternate ? (item.alternate ?? item.run) : item.run
        onClose?()
        action()
    }

    func execute(_ item: CommandItem) {
        guard let index = results.firstIndex(where: { $0.id == item.id }) else { return }
        selection = index
        execute()
    }

    // MARK: Ranking

    func update() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = q.isEmpty ? Self.suggestions(model: self) : rank(q)
        selection = min(selection, max(0, results.count - 1))
        if q.isEmpty { selection = 0 }
    }

    private func rank(_ q: String) -> [CommandItem] {
        var items: [CommandItem] = []
        items += instantAnswers(q)
        items += blinkoActions(q)
        items += AppIndex.shared.matches(q)
        items += ShortcutsIndex.shared.matches(q)
        items += shelfMatches(q)
        items += clipboardMatches(q)
        items.sort { $0.score > $1.score }

        var top = Array(items.prefix(Self.maxResults - 1))
        top.append(webItem(q))
        // Calculator / conversion results first; otherwise selection starts at the best match.
        selection = 0
        return top
    }

    // MARK: Instant answers

    private func instantAnswers(_ q: String) -> [CommandItem] {
        var out: [CommandItem] = []
        if Calculator.looksLikeExpression(q) {
            switch Result(catching: { try Calculator.evaluate(q) }) {
            case .success(let value):
                let text = Calculator.format(value)
                out.append(CommandItem(id: "calc", kind: .calculator, title: text, subtitle: q,
                                       icon: .symbol("equal", .orange), score: 3000,
                                       verb: String(localized: "Copy")) {
                    Self.copy(text.replacingOccurrences(of: ",", with: ""))
                })
            case .failure(let error):
                if let failure = error as? Calculator.Failure, failure != .syntax {
                    out.append(CommandItem(id: "calc", kind: .placeholder, title: Self.message(failure), subtitle: q,
                                           icon: .symbol("exclamationmark.triangle.fill", .orange), score: 3000) {})
                }
            }
        }
        if let (result, source) = UnitConversion.convert(q) {
            let text = UnitConversion.format(result)
            out.append(CommandItem(id: "unit", kind: .conversion, title: text, subtitle: UnitConversion.format(source),
                                   icon: .symbol("arrow.left.arrow.right", .teal), score: 2900,
                                   verb: String(localized: "Copy")) {
                Self.copy(text)
            })
        }
        let rates = CurrencyRates.shared
        if let parsed = CurrencyQuery.parse(q, known: rates.knownCodes) {
            let target = parsed.to ?? Self.defaultTarget(for: parsed.from)
            if let value = rates.convert(parsed.amount, from: parsed.from, to: target) {
                let text = Self.money(value, target)
                out.append(CommandItem(id: "fx", kind: .currency, title: text,
                                       subtitle: "\(Self.money(parsed.amount, parsed.from)) · \(rates.asOfText)",
                                       icon: .symbol("dollarsign.arrow.circlepath", .green), score: 2800,
                                       verb: String(localized: "Copy")) {
                    Self.copy(text)
                })
            } else if !rates.isFresh || rates.isFetching {
                rates.refreshIfNeeded { [weak self] in self?.update() }
                let failed = rates.lastError != nil && !rates.isFetching
                out.append(CommandItem(id: "fx", kind: .placeholder,
                                       title: failed ? String(localized: "Exchange rates unavailable")
                                                     : String(localized: "Fetching exchange rates…"),
                                       subtitle: "\(parsed.from) → \(target)",
                                       icon: .symbol("dollarsign.arrow.circlepath", .green), score: 2800) {})
            }
        }
        return out
    }

    private static func message(_ failure: Calculator.Failure) -> String {
        switch failure {
        case .divisionByZero: String(localized: "Can't divide by zero")
        case .notANumber: String(localized: "Not a number")
        case .overflow: String(localized: "Number too large")
        case .tooComplex: String(localized: "Expression too complex")
        case .syntax: ""
        }
    }

    private static func defaultTarget(for from: String) -> String {
        let local = Locale.current.currency?.identifier ?? "USD"
        if local != from { return local }
        return from == "USD" ? "EUR" : "USD"
    }

    private static func money(_ value: Double, _ code: String) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(Swift.abs(value) < 1 ? 4 : 2)))
    }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: Blinko actions

    private struct Action {
        let id: String
        let title: String
        let keywords: [String]
        let icon: CommandIcon
        let run: @MainActor (CommandBarModel) -> Void
    }

    private static var actions: [Action] {
        var list: [Action] = [
            Action(id: "focus", title: String(localized: "Start focus session"), keywords: ["focus", "pomodoro"],
                   icon: .symbol("brain.head.profile.fill", .orange)) { _ in TimerService.shared.startFocus() },
            Action(id: "awake", title: KeepAwakeService.shared.isActive ? String(localized: "Stop Keep Awake")
                                                                        : String(localized: "Keep awake for 1 hour"),
                   keywords: ["keep awake", "caffeinate", "awake", "amphetamine"],
                   icon: .symbol("cup.and.saucer.fill", .orange)) { _ in
                let awake = KeepAwakeService.shared
                awake.isActive ? awake.stop() : awake.start(for: 3600)
            },
            Action(id: "mic", title: AudioLevels.isMuted(.input) ? String(localized: "Unmute microphone")
                                                                 : String(localized: "Mute microphone"),
                   keywords: ["mute", "unmute", "microphone", "mic"],
                   icon: .symbol("mic.slash.fill", .red)) { _ in
                AudioLevels.setMuted(.input, !AudioLevels.isMuted(.input))
            },
            Action(id: "settings", title: String(localized: "Blinko Settings"), keywords: ["settings", "preferences"],
                   icon: .symbol("gearshape.fill", .gray)) { _ in SettingsWindowController.shared.show() },
        ]
        for tab in NotchTab.allCases {
            list.append(Action(id: "tab-\(tab.rawValue)", title: String(localized: "Open \(tab.title)"),
                               keywords: [tab.title, "open \(tab.title)"],
                               icon: .symbol(tab.symbol, .blue)) { model in model.onShowTab?(tab) })
        }
        return list
    }

    private func blinkoActions(_ q: String) -> [CommandItem] {
        var out: [CommandItem] = []
        let lower = q.lowercased()
        // "t 5m", "timer 1h30", "timer 25"
        for prefix in ["t ", "timer "] where lower.hasPrefix(prefix) {
            if let seconds = DurationParser.parse(String(lower.dropFirst(prefix.count))) {
                out.append(CommandItem(id: "timer", kind: .action,
                                       title: String(localized: "Start a \(Format.duration(seconds)) timer"),
                                       icon: .symbol("timer", .orange), score: 2500,
                                       verb: String(localized: "Start")) {
                    TimerService.shared.start(seconds, label: Format.duration(seconds))
                })
            }
        }
        // "awake 2h"
        if lower.hasPrefix("awake "), let seconds = DurationParser.parse(String(lower.dropFirst(6))) {
            out.append(CommandItem(id: "awake-for", kind: .action,
                                   title: String(localized: "Keep awake for \(Format.duration(seconds))"),
                                   icon: .symbol("cup.and.saucer.fill", .orange), score: 2500,
                                   verb: String(localized: "Start")) {
                KeepAwakeService.shared.start(for: seconds)
            })
        }
        for action in Self.actions {
            let best = ([action.title] + action.keywords).compactMap { FuzzyMatcher.score(q, in: $0) }.max()
            guard let best, best >= 300 || q.count >= 3 && best > 0 else { continue }
            out.append(CommandItem(id: "action-\(action.id)", kind: .action, title: action.title,
                                   icon: action.icon, score: best + 120,
                                   verb: String(localized: "Run")) { [weak self] in
                if let self { action.run(self) }
            })
        }
        return out
    }

    private static func suggestions(model: CommandBarModel) -> [CommandItem] {
        let five = TimeInterval(300)
        return [
            CommandItem(id: "s-timer", kind: .action, title: String(localized: "Start a \(Format.duration(five)) timer"),
                        subtitle: String(localized: "Type “t 25m” for any length"),
                        icon: .symbol("timer", .orange), verb: String(localized: "Start")) {
                TimerService.shared.start(five, label: Format.duration(five))
            },
            CommandItem(id: "s-focus", kind: .action, title: String(localized: "Start focus session"),
                        icon: .symbol("brain.head.profile.fill", .orange), verb: String(localized: "Start")) {
                TimerService.shared.startFocus()
            },
            CommandItem(id: "s-calc", kind: .placeholder, title: String(localized: "Calculate"),
                        subtitle: "(12 + 4) * 3^2 / 5", icon: .symbol("equal", .orange)) {},
            CommandItem(id: "s-convert", kind: .placeholder, title: String(localized: "Convert units & currency"),
                        subtitle: "10 km to mi · 100 usd in eur", icon: .symbol("arrow.left.arrow.right", .teal)) {},
            CommandItem(id: "s-shelf", kind: .action, title: String(localized: "Open Shelf"),
                        icon: .symbol(NotchTab.shelf.symbol, .blue)) { [weak model] in model?.onShowTab?(.shelf) },
            CommandItem(id: "s-clip", kind: .action, title: String(localized: "Open Clipboard"),
                        icon: .symbol(NotchTab.clipboard.symbol, .blue)) { [weak model] in model?.onShowTab?(.clipboard) },
        ]
    }

    // MARK: Shelf, clipboard, web

    private func shelfMatches(_ q: String) -> [CommandItem] {
        ShelfService.shared.items.compactMap { item in
            guard let score = FuzzyMatcher.score(q, in: item.name) else { return nil }
            return CommandItem(id: "shelf-\(item.id)", kind: .shelf, title: item.name,
                               subtitle: String(localized: "On the shelf · ⌘↩ shows in Finder"),
                               icon: .file(item.url), score: score) {
                ShelfService.shared.open(item)
            } alternate: {
                ShelfService.shared.reveal(item)
            }
        }
    }

    private func clipboardMatches(_ q: String) -> [CommandItem] {
        ClipboardService.shared.items.prefix(50).compactMap { clip in
            let preview = String(clip.preview.prefix(300)).replacingOccurrences(of: "\n", with: " ")
            let score: Double
            if preview.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                score = 450 - Double(min(preview.count, 200)) * 0.2
            } else if q.count >= 3, let fuzzy = FuzzyMatcher.score(q, in: String(preview.prefix(60))), fuzzy > 60 {
                score = fuzzy * 0.5
            } else {
                return nil
            }
            let icon: CommandIcon
            switch clip.content {
            case .text: icon = .symbol("doc.on.clipboard.fill", .purple)
            case .image(let image): icon = .image(image)
            case .files(let urls): icon = urls.first.map(CommandIcon.file) ?? .symbol("doc.fill", .purple)
            }
            return CommandItem(id: "clip-\(clip.id)", kind: .clipboard, title: String(preview.prefix(90)),
                               subtitle: clip.sourceApp.map { String(localized: "Copied from \($0)") } ?? "",
                               icon: icon, score: score, verb: String(localized: "Copy")) {
                ClipboardService.shared.copy(clip)
            }
        }
    }

    private func webItem(_ q: String) -> CommandItem {
        if let url = Self.urlLike(q) {
            return CommandItem(id: "web", kind: .web, title: String(localized: "Open \(url.host ?? q)"),
                               subtitle: url.absoluteString, icon: .symbol("safari.fill", .blue)) {
                NSWorkspace.shared.open(url)
            }
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: q)]
        let url = components.url!
        return CommandItem(id: "web", kind: .web, title: String(localized: "Search the web for “\(q)”"),
                           icon: .symbol("magnifyingglass", .blue), verb: String(localized: "Search")) {
            NSWorkspace.shared.open(url)
        }
    }

    /// "github.com", "https://x.y/z" → URL; anything with spaces or no dot → nil.
    static func urlLike(_ q: String) -> URL? {
        guard !q.contains(" "), q.contains("."), !q.hasSuffix("."), !Calculator.looksLikeExpression(q) else { return nil }
        let text = q.contains("://") ? q : "https://\(q)"
        guard let url = URL(string: text), let host = url.host, host.contains("."),
              let tld = host.split(separator: ".").last, tld.count >= 2, tld.allSatisfy(\.isLetter)
        else { return nil }
        return url
    }

    // MARK: Preview

    func injectPreview(query: String) {
        isPreview = true
        self.query = query
        update()
    }
}

// MARK: - Apps

/// Installed applications, scanned on the first command-bar open (off main) and refreshed at
/// most every 10 minutes while the bar is used. Icons are fetched for visible rows only.
@MainActor
final class AppIndex {
    static let shared = AppIndex()

    struct Entry: Sendable {
        let name: String
        let url: URL
    }

    private(set) var entries: [Entry] = []
    private var loadedAt: Date?
    private var loading = false

    func loadIfNeeded(_ completion: @escaping @MainActor () -> Void) {
        guard !loading, loadedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? true else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let found = Self.scan()
            await MainActor.run {
                let index = AppIndex.shared
                index.entries = found
                index.loadedAt = Date()
                index.loading = false
                completion()
            }
        }
    }

    nonisolated static func scan() -> [Entry] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "\(home)/Applications",
                     "/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices/Applications"]
        var seen = Set<String>()
        var out: [Entry] = []
        func add(_ path: String) {
            let url = URL(fileURLWithPath: path)
            let id = Bundle(url: url)?.bundleIdentifier ?? path
            guard seen.insert(id).inserted else { return }
            out.append(Entry(name: fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), url: url))
        }
        for root in roots {
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = "\(root)/\(name)"
                if name.hasSuffix(".app") {
                    add(path)
                } else if root == "/Applications" || root.hasSuffix("/Applications"),
                          let inner = try? fm.contentsOfDirectory(atPath: path) {
                    // One level of folders ("Adobe Photoshop 2026/Adobe Photoshop 2026.app").
                    inner.filter { $0.hasSuffix(".app") }.forEach { add("\(path)/\($0)") }
                }
            }
        }
        add("/System/Library/CoreServices/Finder.app")
        return out
    }

    /// Snapshot rendering: scan synchronously.
    func injectPreview() {
        entries = Self.scan()
        loadedAt = Date()
    }

    func matches(_ q: String) -> [CommandItem] {
        entries.compactMap { entry in
            guard let score = FuzzyMatcher.score(q, in: entry.name) else { return nil }
            return CommandItem(id: "app-\(entry.url.path)", kind: .app, title: entry.name, icon: .file(entry.url),
                               score: score + 60, verb: String(localized: "Launch")) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: entry.url, configuration: config)
            } alternate: {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
    }
}

// MARK: - Apple Shortcuts

/// The user's Shortcuts, listed with `shortcuts list` on first open (off main), run with
/// `shortcuts run`.
@MainActor
final class ShortcutsIndex {
    static let shared = ShortcutsIndex()

    private(set) var names: [String] = []
    private var loadedAt: Date?
    private var loading = false
    nonisolated private static let tool = "/usr/bin/shortcuts"

    func loadIfNeeded(_ completion: @escaping @MainActor () -> Void) {
        guard !loading, FileManager.default.isExecutableFile(atPath: Self.tool),
              loadedAt.map({ Date().timeIntervalSince($0) > 600 }) ?? true else { return }
        loading = true
        Task.detached(priority: .utility) {
            let output = Self.runTool(["list"])
            let list = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            await MainActor.run {
                let index = ShortcutsIndex.shared
                index.names = list
                index.loadedAt = Date()
                index.loading = false
                completion()
            }
        }
    }

    nonisolated private static func runTool(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func injectPreview(_ names: [String]) {
        self.names = names
        loadedAt = Date()
    }

    func matches(_ q: String) -> [CommandItem] {
        names.compactMap { name in
            guard let score = FuzzyMatcher.score(q, in: name) else { return nil }
            return CommandItem(id: "shortcut-\(name)", kind: .shortcut, title: name,
                               icon: .symbol("square.2.layers.3d.top.filled", .pink), score: score + 20,
                               verb: String(localized: "Run")) {
                Self.run(name)
            }
        }
    }

    static func run(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run() // runs on its own; nothing waits for it
    }
}

// MARK: - Currency rates

/// Daily exchange rates from open.er-api.com (free, no key), base USD. Fetched only when a
/// currency query is typed and the cache is older than a day; cached in UserDefaults.
@MainActor
final class CurrencyRates {
    static let shared = CurrencyRates()

    private(set) var rates: [String: Double] = [:]
    private(set) var updated: Date?
    private(set) var isFetching = false
    private(set) var lastError: Error?
    private var lastAttempt = Date.distantPast
    private let key = "currencyRates.v1"

    private struct Stored: Codable {
        let rates: [String: Double]
        let updated: Date
    }

    private struct Response: Decodable {
        let result: String
        let rates: [String: Double]?
        let time_last_update_unix: Double?
    }

    static let common: Set<String> = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD", "CNY", "HKD", "SGD",
                                      "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "INR", "KRW", "BRL", "MXN", "ZAR",
                                      "TRY", "AED", "SAR", "ILS", "THB", "IDR", "MYR", "PHP", "TWD", "RON"]

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            rates = stored.rates
            updated = stored.updated
        }
    }

    var knownCodes: Set<String> { rates.isEmpty ? Self.common : Set(rates.keys) }

    var isFresh: Bool { updated.map { Date().timeIntervalSince($0) < 86_400 } ?? false }

    var asOfText: String {
        guard let updated else { return "" }
        return String(localized: "rates of \(updated.formatted(date: .abbreviated, time: .omitted))")
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        if !isFresh { refreshIfNeeded {} } // keep using yesterday's rates meanwhile
        guard let a = rates[from], let b = rates[to], a > 0 else { return nil }
        return amount / a * b
    }

    func refreshIfNeeded(_ completion: @escaping @MainActor () -> Void) {
        guard !isFresh, !isFetching, Date().timeIntervalSince(lastAttempt) > 60 else { return }
        isFetching = true
        lastAttempt = Date()
        Task {
            do {
                let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try await Task.detached { try JSONDecoder().decode(Response.self, from: data) }.value
                guard decoded.result == "success", let rates = decoded.rates, !rates.isEmpty else {
                    throw URLError(.cannotParseResponse)
                }
                self.rates = rates
                // Freshness counts from our fetch: the upstream timestamp can be up to a day old.
                let now = Date()
                self.updated = now
                lastError = nil
                if let data = try? JSONEncoder().encode(Stored(rates: rates, updated: now)) {
                    UserDefaults.standard.set(data, forKey: key)
                }
            } catch {
                lastError = error
            }
            isFetching = false
            completion()
        }
    }

    func injectPreview(_ rates: [String: Double]) {
        self.rates = rates
        updated = Date()
    }
}
