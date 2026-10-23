import CryptoKit
import Foundation
import Observation
import SwiftUI

/// Time-synced lyrics from LRCLIB (lrclib.net, free, no key).
///
/// Nothing is fetched in the background: views that show lyrics call `load` from
/// `.task(id: track)`, so a request happens only on a track change while the player (or the
/// compact-lyrics wing) is on screen. Results are cached in memory (NSCache) and on disk in
/// Application Support (misses too, so unknown tracks aren't asked for again). Network and
/// parsing run off the main actor.
@MainActor
@Observable
final class LyricsService {
    static let shared = LyricsService()

    struct Line: Equatable {
        let time: TimeInterval
        let text: String
    }

    /// Lines for `trackKey`; empty while loading or when the track has no synced lyrics.
    private(set) var lines: [Line] = []
    private(set) var trackKey = ""

    @ObservationIgnored private let memory = NSCache<NSString, LinesBox>()
    @ObservationIgnored private var inFlight: String?

    private nonisolated static let cacheDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Blinko/Lyrics", isDirectory: true)
    }()

    private init() {
        memory.countLimit = 40
    }

    static func key(title: String, artist: String) -> String { title + "\u{1}" + artist }

    func hasLyrics(for key: String) -> Bool { trackKey == key && !lines.isEmpty }

    /// Index of the line being sung at `elapsed` (nil before the first line).
    func lineIndex(at elapsed: TimeInterval) -> Int? {
        guard let first = lines.first, elapsed >= first.time else { return nil }
        var lo = 0, hi = lines.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lines[mid].time <= elapsed { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func load(title: String, artist: String, album: String, duration: TimeInterval) async {
        guard !title.isEmpty else { return }
        let key = Self.key(title: title, artist: artist)
        guard key != trackKey || lines.isEmpty, inFlight != key else { return }
        if key != trackKey {
            trackKey = key
            lines = []
        }
        if let cached = memory.object(forKey: key as NSString) {
            lines = cached.lines
            return
        }
        inFlight = key
        defer { if inFlight == key { inFlight = nil } }
        let found = await Self.fetch(key: key, title: title, artist: artist, album: album, duration: duration)
        memory.setObject(LinesBox(found), forKey: key as NSString)
        if trackKey == key, lines != found { lines = found }
    }

    // MARK: Fetching (off main)

    private nonisolated static func fetch(key: String, title: String, artist: String, album: String,
                                          duration: TimeInterval) async -> [Line] {
        let file = cacheDirectory.appendingPathComponent(hash(key) + ".lrc")
        if let cached = try? String(contentsOf: file, encoding: .utf8) { return parse(cached) }

        var lrc: String?
        var definitive = false // a clean "not found" is cached; network errors are not
        if let (text, ok) = await request(path: "get", items: query(title: title, artist: artist, album: album, duration: duration)) {
            lrc = text
            definitive = ok
        }
        if lrc == nil, definitive {
            // No exact match: search and take the closest synced result.
            if let (text, _) = await request(path: "search", items: [.init(name: "track_name", value: title),
                                                                      .init(name: "artist_name", value: artist)],
                                             duration: duration) {
                lrc = text
            }
        }
        if lrc != nil || definitive { store(lrc ?? "", at: file) }
        return parse(lrc ?? "")
    }

    private nonisolated static func query(title: String, artist: String, album: String, duration: TimeInterval) -> [URLQueryItem] {
        var items: [URLQueryItem] = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        if !album.isEmpty { items.append(.init(name: "album_name", value: album)) }
        if duration > 0 { items.append(.init(name: "duration", value: String(Int(duration.rounded())))) }
        return items
    }

    /// Returns (synced lyrics or nil, whether the server answered definitively), or nil on error.
    private nonisolated static func request(path: String, items: [URLQueryItem], duration: TimeInterval = 0) async -> (String?, Bool)? {
        var c = URLComponents(string: "https://lrclib.net/api/\(path)")!
        c.queryItems = items
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        req.setValue("Blinko/\(version) (https://github.com/techInnovator1999/Blinko)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if status == 404 { return (nil, true) }
        guard status == 200 else { return nil }

        if path == "search" {
            guard let results = try? JSONDecoder().decode([LRCLibTrack].self, from: data) else { return (nil, true) }
            let synced = results.filter { ($0.syncedLyrics ?? "").isEmpty == false }
            let best = duration > 0
                ? synced.min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
                : synced.first
            if let best, duration <= 0 || abs((best.duration ?? 0) - duration) < 4 { return (best.syncedLyrics, true) }
            return (nil, true)
        }
        let track = try? JSONDecoder().decode(LRCLibTrack.self, from: data)
        let lyrics = track?.syncedLyrics
        return ((lyrics?.isEmpty ?? true) ? nil : lyrics, true)
    }

    /// Parses "[mm:ss.xx] text" lines (several timestamps per line allowed), sorted by time.
    nonisolated static func parse(_ lrc: String) -> [Line] {
        var result: [Line] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                let parts = tag.split(separator: ":")
                guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { continue }
                times.append(m * 60 + s)
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times { result.append(Line(time: t, text: text)) }
        }
        return result.sorted { $0.time < $1.time }
    }

    private nonisolated static func hash(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes one cache file and keeps the folder small (oldest entries pruned past 400).
    private nonisolated static func store(_ text: String, at file: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
        guard let entries = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]),
              entries.count > 400 else { return }
        let dated = entries.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(entries.count - 350) {
            try? fm.removeItem(at: url)
        }
    }

    /// Design-time data for snapshot rendering.
    func injectPreview(key: String, lrc: String) {
        trackKey = key
        lines = Self.parse(lrc)
    }
}

private final class LinesBox {
    let lines: [LyricsService.Line]
    init(_ lines: [LyricsService.Line]) { self.lines = lines }
}

private struct LRCLibTrack: Decodable {
    var syncedLyrics: String?
    var duration: Double?
}

/// Fires exactly when the next lyric line starts (plus once now), instead of polling.
/// Rebuilt whenever playback state changes (pause, seek, track change).
struct LyricsSchedule: TimelineSchedule {
    let dates: [Date]

    @MainActor
    init(lines: [LyricsService.Line], player np: NowPlayingService) {
        guard np.isPlaying, !lines.isEmpty else { dates = []; return }
        let now = Date()
        let elapsed = np.elapsed(at: now)
        let rate = max(np.rate, 1)
        dates = lines.lazy.filter { $0.time > elapsed }
            .map { now.addingTimeInterval(($0.time - elapsed) / rate) }
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> [Date] {
        [startDate] + dates.filter { $0 > startDate }
    }
}
