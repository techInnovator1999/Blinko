import AppKit
import Observation

/// Now Playing for every source (Music, Spotify, browsers, video players…).
///
/// Primary path: the BlinkoMedia helper running inside /usr/bin/perl (the only way to
/// read MediaRemote on macOS 15.4+). Output is read in chunks off the main thread and
/// parsed there; only the final state hops to the main actor. Artwork is decoded once
/// per track. If the helper can't run, falls back to Music/Spotify distributed
/// notifications (no polling either way).
@MainActor
@Observable
final class NowPlayingService {
    static let shared = NowPlayingService()

    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    private(set) var accent: NSColor = .white
    private(set) var bundleID: String?
    /// Elapsed position anchored at `anchorDate`; current position is extrapolated on read.
    private(set) var anchorElapsed: TimeInterval = 0
    private(set) var anchorDate = Date()
    private(set) var rate: Double = 0

    var hasTrack: Bool { !title.isEmpty }

    func elapsed(at date: Date = .now) -> TimeInterval {
        let value = anchorElapsed + (isPlaying ? date.timeIntervalSince(anchorDate) * max(rate, 1) : 0)
        return duration > 0 ? min(max(value, 0), duration) : max(value, 0)
    }

    var appIcon: NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdinPipe: Pipe?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var usingFallback = false
    @ObservationIgnored private var lastArtworkID: Int = -1
    @ObservationIgnored private var lastTrackKey = ""

    /// Design-time data for snapshot rendering.
    func injectPreview(title: String, artist: String, duration: TimeInterval, elapsed: TimeInterval,
                       playing: Bool, artwork: NSImage?) {
        self.title = title; self.artist = artist; self.duration = duration
        anchorElapsed = elapsed; anchorDate = .now; isPlaying = playing; rate = 1
        self.artwork = artwork; accent = artwork?.dominantAccent() ?? .white
    }

    // MARK: Lifecycle

    func start() {
        startHelper()
    }

    func stop() {
        stdinPipe?.fileHandleForWriting.closeFile() // helper exits on EOF
        process = nil
    }

    // MARK: Commands

    func togglePlayPause() { send("toggle", fallback: "playpause") }
    func next() { send("next", fallback: "next track") }
    func previous() { send("previous", fallback: "previous track") }

    func seek(to seconds: TimeInterval) {
        anchorElapsed = seconds
        anchorDate = .now
        if usingFallback {
            runScript("set player position to \(seconds)")
        } else {
            write("seek \(seconds)")
        }
    }

    func openSourceApp() {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ command: String, fallback: String) {
        if usingFallback { runScript(fallback) } else { write(command) }
    }

    private func write(_ line: String) {
        guard let handle = stdinPipe?.fileHandleForWriting else { return }
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }

    // MARK: Helper process

    private func startHelper() {
        guard let resources = Bundle.main.resourceURL else { return enableFallback() }
        let script = resources.appendingPathComponent("blinko-media.pl")
        let dylib = resources.appendingPathComponent("BlinkoMedia.dylib")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: dylib.path) else { return enableFallback() }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, dylib.path]
        let out = Pipe(), input = Pipe()
        p.standardOutput = out
        p.standardInput = input
        p.standardError = FileHandle.nullDevice
        p.qualityOfService = .utility

        let reader = LineReader { [weak self] line in
            guard let payload = MediaPayload(line: line) else { return }
            DispatchQueue.main.async { self?.apply(payload) }
        }
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            reader.feed(data)
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.helperExited(status: proc.terminationStatus) }
        }

        do {
            try p.run()
            process = p
            stdinPipe = input
        } catch {
            NSLog("Blinko: media helper failed to launch: \(error.localizedDescription)")
            enableFallback()
        }
    }

    private func helperExited(status: Int32) {
        NSLog("Blinko: media helper exited (\(status))")
        process = nil
        stdinPipe = nil
        failures += 1
        if failures >= 3 {
            enableFallback()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(failures)) { [weak self] in self?.startHelper() }
        }
    }

    private func apply(_ p: MediaPayload) {
        if p.isError { failures = 3; return }
        guard p.isState else { return }
        failures = 0

        let trackKey = p.title + "\u{1}" + p.artist
        let trackChanged = trackKey != lastTrackKey && !p.title.isEmpty
        lastTrackKey = trackKey

        if title != p.title { title = p.title }
        if artist != p.artist { artist = p.artist }
        if album != p.album { album = p.album }
        if duration != p.duration { duration = p.duration }
        if bundleID != p.bundle { bundleID = p.bundle }
        rate = p.rate
        anchorElapsed = p.elapsed
        anchorDate = p.timestamp
        if isPlaying != p.playing { isPlaying = p.playing }

        if p.artworkID != lastArtworkID {
            lastArtworkID = p.artworkID
            if p.artworkID == 0 {
                artwork = nil
                accent = .white
            } else if let image = p.artwork {
                artwork = image
                accent = image.dominantAccent()
            }
        }

        if trackChanged, p.playing, Preferences.shared.musicActivity {
            ActivityCenter.shared.show(.nowPlayingChanged)
        }
    }

    // MARK: Fallback (Music + Spotify)

    private func enableFallback() {
        guard !usingFallback else { return }
        usingFallback = true
        let dnc = DistributedNotificationCenter.default()
        for (name, bundle) in [("com.apple.Music.playerInfo", "com.apple.Music"),
                               ("com.spotify.client.PlaybackStateChanged", "com.spotify.client")] {
            dnc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.applyFallback(info, bundle: bundle) }
            }
        }
    }

    private func applyFallback(_ info: [AnyHashable: Any], bundle: String) {
        let state = info["Player State"] as? String ?? ""
        let playing = state == "Playing"
        let name = info["Name"] as? String ?? ""
        let changed = name != title
        title = name
        artist = info["Artist"] as? String ?? ""
        album = info["Album"] as? String ?? ""
        // Both players report milliseconds.
        let millis = (info["Total Time"] as? NSNumber) ?? (info["Duration"] as? NSNumber)
        duration = (millis?.doubleValue ?? 0) / 1000
        if let pos = info["Playback Position"] as? Double { anchorElapsed = pos; anchorDate = .now }
        rate = playing ? 1 : 0
        bundleID = bundle
        isPlaying = playing
        if changed { fetchFallbackArtwork(bundle: bundle) }
    }

    private func fetchFallbackArtwork(bundle: String) {
        guard bundle == "com.spotify.client" else { artwork = nil; return }
        let source = "tell application id \"com.spotify.client\" to get artwork url of current track"
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            guard let urlString = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue,
                  let url = URL(string: urlString),
                  let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data) else { return }
            let accent = image.dominantAccent()
            DispatchQueue.main.async { [weak self] in
                self?.artwork = image
                self?.accent = accent
            }
        }
    }

    private func runScript(_ command: String) {
        let bundle = bundleID ?? "com.apple.Music"
        let source = "tell application id \"\(bundle)\" to \(command)"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}

// MARK: - Parsing (off main thread)

private struct MediaPayload: @unchecked Sendable {
    var isState = false
    var isError = false
    var title = "", artist = "", album = ""
    var duration: Double = 0, elapsed: Double = 0, rate: Double = 0
    var timestamp = Date()
    var playing = false
    var bundle: String?
    var artworkID = 0
    var artwork: NSImage?

    init?(line: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = json["type"] as? String else { return nil }
        isError = type == "error"
        isState = type == "state"
        title = json["title"] as? String ?? ""
        artist = json["artist"] as? String ?? ""
        album = json["album"] as? String ?? ""
        duration = (json["duration"] as? NSNumber)?.doubleValue ?? 0
        elapsed = (json["elapsed"] as? NSNumber)?.doubleValue ?? 0
        rate = (json["rate"] as? NSNumber)?.doubleValue ?? 0
        if let ts = (json["timestamp"] as? NSNumber)?.doubleValue { timestamp = Date(timeIntervalSince1970: ts) }
        playing = (json["playing"] as? NSNumber)?.boolValue ?? false
        bundle = json["bundle"] as? String
        artworkID = (json["artworkId"] as? NSNumber)?.intValue ?? 0
        if let b64 = json["artwork"] as? String, let data = Data(base64Encoded: b64) {
            artwork = NSImage(data: data)?.downsampled(to: 256)
        }
    }
}

/// Accumulates pipe chunks and emits complete lines. Never reads byte-by-byte.
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    private let onLine: (Data) -> Void
    private let maxLine = 8 * 1024 * 1024

    init(onLine: @escaping (Data) -> Void) { self.onLine = onLine }

    func feed(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(Data(buffer[buffer.startIndex..<nl]))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        if buffer.count > maxLine { buffer.removeAll() }
        lock.unlock()
        lines.forEach(onLine)
    }
}
