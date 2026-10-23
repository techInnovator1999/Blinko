import AppKit
import Observation
import QuickLookThumbnailing

struct ShelfItem: Identifiable, Equatable, Codable {
    let id: UUID
    let url: URL
    let addedAt: Date
    var name: String { url.lastPathComponent }
}

/// File shelf: drop anything on the island, drag it out later, AirDrop or share it.
/// Persisted as security-scoped-free plain paths (app is not sandboxed).
@MainActor
@Observable
final class ShelfService {
    static let shared = ShelfService()

    private(set) var items: [ShelfItem] = []
    var selection: Set<UUID> = []

    @ObservationIgnored private let key = "shelfItems"
    @ObservationIgnored private let thumbnails = NSCache<NSURL, NSImage>()

    init() {
        thumbnails.countLimit = 64
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        }
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.map(\.url))
        let new = urls.filter { !existing.contains($0) }.map { ShelfItem(id: UUID(), url: $0, addedAt: .now) }
        guard !new.isEmpty else { return }
        items.append(contentsOf: new)
        persist()
        ActivityCenter.shared.show(.shelf(count: items.count))
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
        persist()
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        persist()
    }

    func open(_ item: ShelfItem) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: ShelfItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func airDrop(_ urls: [URL]) {
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    var selectedOrAll: [URL] {
        let chosen = items.filter { selection.contains($0.id) }
        return (chosen.isEmpty ? items : chosen).map(\.url)
    }

    /// Thumbnails are generated off-main by QuickLook and cached with a bounded NSCache.
    func thumbnail(for url: URL, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        if let cached = thumbnails.object(forKey: url as NSURL) { completion(cached); return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            let image = rep?.nsImage ?? NSWorkspace.shared.icon(forFile: url.path)
            DispatchQueue.main.async {
                self?.thumbnails.setObject(image, forKey: url as NSURL)
                completion(image)
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }
}
