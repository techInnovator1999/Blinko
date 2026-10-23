import AppKit
import Observation

struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
}

/// Scratchpad + snippets, stored as plain files in Application Support. Loaded lazily the
/// first time the Notes tab appears; edits are saved after a short pause (debounced), off main.
@MainActor
@Observable
final class NotesService {
    static let shared = NotesService()

    var text: String { didSet { if text != oldValue { scheduleSave() } } }
    private(set) var snippets: [Snippet]

    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private let queue = DispatchQueue(label: "app.blinko.notes", qos: .utility)

    private nonisolated static let folder: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blinko", isDirectory: true)
    }()
    private nonisolated static var notesFile: URL { folder.appendingPathComponent("Notes.txt") }
    private nonisolated static var snippetsFile: URL { folder.appendingPathComponent("Snippets.json") }

    private init() {
        text = (try? String(contentsOf: Self.notesFile, encoding: .utf8)) ?? ""
        snippets = (try? Data(contentsOf: Self.snippetsFile))
            .flatMap { try? JSONDecoder().decode([Snippet].self, from: $0) } ?? []
    }

    // MARK: Snippets

    func addSnippet(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !snippets.contains(where: { $0.text == trimmed }) else { return }
        snippets.insert(Snippet(text: trimmed), at: 0)
        saveSnippets()
    }

    func removeSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        saveSnippets()
    }

    func copy(_ snippet: Snippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.text, forType: .string)
    }

    /// Saves pending scratchpad edits right away (island closing, app quitting).
    func flush() {
        guard let work = saveWork else { return }
        work.cancel()
        saveWork = nil
        write(text, to: Self.notesFile)
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveWork = nil
            self.write(self.text, to: Self.notesFile)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func saveSnippets() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? data.write(to: Self.snippetsFile, options: .atomic)
        }
    }

    private func write(_ value: String, to url: URL) {
        queue.async {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? value.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Design-time data for snapshot rendering (not saved).
    func injectPreview(text: String, snippets: [String]) {
        saveWork?.cancel()
        self.text = text
        saveWork?.cancel()
        saveWork = nil
        self.snippets = snippets.map { Snippet(text: $0) }
    }
}
