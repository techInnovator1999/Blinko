import Foundation
import Observation

/// Browser download progress from ~/Downloads.
///
/// A DispatchSource on the folder fires when entries appear, vanish or are renamed. Sizes
/// are sampled at 2 Hz only while a partial download exists (Safari `.download` bundles,
/// Chrome `.crdownload`, Firefox `.part`); with no partial file there is no timer at all.
/// All file I/O happens on a utility queue.
@MainActor
@Observable
final class DownloadsService {
    static let shared = DownloadsService()

    struct Progress: Equatable {
        var name: String
        var received: Int64
        /// Known for Safari only; Chrome and Firefox don't record the final size on disk.
        var total: Int64?
        var fraction: Double? {
            guard let total, total > 0 else { return nil }
            return min(Double(received) / Double(total), 1)
        }
    }

    /// The download shown in the island (the largest one when several run).
    private(set) var active: Progress?
    private(set) var activeCount = 0
    /// Most recently finished download (offered on the shelf for a few minutes).
    private(set) var recent: URL?

    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var poll: Timer?
    @ObservationIgnored private var partials: [URL: String] = [:] // partial file → final name
    @ObservationIgnored private var recentExpiry: DispatchWorkItem?
    @ObservationIgnored private let queue = DispatchQueue(label: "app.blinko.downloads", qos: .utility)

    private nonisolated static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    private nonisolated static let partialSuffixes = [".download", ".crdownload", ".part"]

    func refresh() {
        Preferences.shared.downloadsActivity ? start() : stop()
    }

    private func start() {
        guard source == nil else { return }
        let fd = open(Self.folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: queue)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        queue.async { [weak self] in self?.scan(initial: true) }
    }

    private func stop() {
        source?.cancel()
        source = nil
        stopPolling()
        partials.removeAll()
        active = nil
        activeCount = 0
    }

    /// Marks a finished download as handled (added to the shelf).
    func clearRecent() { recent = nil }

    // MARK: Scanning (utility queue)

    private nonisolated func scan(initial: Bool = false) {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil,
                                                   options: [.skipsHiddenFiles])) ?? []
        var found: [URL: String] = [:]
        for url in entries {
            let name = url.lastPathComponent
            guard let suffix = Self.partialSuffixes.first(where: { name.hasSuffix($0) }) else { continue }
            found[url] = String(name.dropLast(suffix.count))
        }
        let samples = found.map { Self.sample($0.key, name: $0.value) }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.update(found: found, samples: samples, initial: initial) }
        }
    }

    private nonisolated static func sample(_ url: URL, name: String) -> Progress {
        let fm = FileManager.default
        if url.pathExtension == "download" {
            // Safari bundle: Info.plist records the expected size; the data file grows beside it.
            var total: Int64?
            var received: Int64 = 0
            if let plist = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) {
                total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
                received = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
            }
            let files = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let onDisk = files.filter { $0.lastPathComponent != "Info.plist" }
                .reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return Progress(name: name, received: max(received, onDisk), total: total.flatMap { $0 > 0 ? $0 : nil })
        }
        let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return Progress(name: name, received: size, total: nil)
    }

    // MARK: State (main)

    private func update(found: [URL: String], samples: [Progress], initial: Bool) {
        guard source != nil else { return }
        // Partials that vanished have either finished (final file exists) or were cancelled.
        if !initial {
            for (url, name) in partials where found[url] == nil {
                let final = Self.folder.appendingPathComponent(name)
                queue.async { [weak self] in
                    let resolved = Self.resolveFinished(final, partial: url)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { if let resolved { self?.finished(resolved) } }
                    }
                }
            }
        }
        partials = found
        activeCount = found.count
        let primary = samples.max { $0.received < $1.received }
        if active != primary { active = primary }
        found.isEmpty ? stopPolling() : startPolling()
    }

    /// Finds the completed file. Chrome may have used a temporary "Unconfirmed" name, so
    /// fall back to the newest file that appeared in the last few seconds.
    private nonisolated static func resolveFinished(_ expected: URL, partial: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: expected.path),
           ((try? fm.attributesOfItem(atPath: expected.path)[.size] as? NSNumber)?.int64Value ?? 0) > 0 || partial.pathExtension == "download" {
            return expected
        }
        let entries = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.addedToDirectoryDateKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        return entries
            .filter { url in !partialSuffixes.contains { url.lastPathComponent.hasSuffix($0) } }
            .compactMap { url -> (URL, Date)? in
                guard let added = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate,
                      Date().timeIntervalSince(added) < 5 else { return nil }
                return (url, added)
            }
            .max { $0.1 < $1.1 }?.0
    }

    private func finished(_ url: URL) {
        recent = url
        recentExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recent = nil }
        recentExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
        guard Preferences.shared.downloadsActivity else { return }
        ActivityCenter.shared.show(.downloadFinished(name: url.lastPathComponent, url: url))
    }

    private func startPolling() {
        guard poll == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = self.partials
                self.queue.async { [weak self] in
                    let samples = current.map { Self.sample($0.key, name: $0.value) }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, !self.partials.isEmpty else { return }
                            let primary = samples.max { $0.received < $1.received }
                            if self.active != primary { self.active = primary }
                        }
                    }
                }
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    /// Design-time state for snapshot rendering.
    func injectPreview(_ progress: Progress?, count: Int = 1, recent: URL? = nil) {
        active = progress
        activeCount = progress == nil ? 0 : count
        self.recent = recent
    }
}
