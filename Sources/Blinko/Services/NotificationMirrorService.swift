import AppKit
import ApplicationServices
import Observation
import os

private let log = Logger(subsystem: "app.blinko.Blinko", category: "notifications")

/// A notification banner mirrored into the island (e.g. a Slack message).
struct MirroredNotification: Equatable {
    let id: String
    let app: String
    let title: String
    let subtitle: String?
    let body: String?
}

/// Mirrors other apps' notification banners (Slack by default) into the island.
///
/// macOS has no public API for other apps' notifications, so this reads the banner the
/// system is already showing, via the Accessibility permission Blinko has for the HUD.
/// Event-driven: an AXObserver on Notification Center fires when a banner appears;
/// nothing runs in between. Banners are identified by their unique id, so a banner is
/// mirrored once; opening the Notification Center list never floods the island.
@MainActor
@Observable
final class NotificationMirrorService {
    static let shared = NotificationMirrorService()

    /// Apps offered in Settings (display names as macOS shows them on banners).
    static let suggestedApps = ["Slack", "Messages", "WhatsApp", "Microsoft Teams", "Discord", "Mail", "Telegram"]

    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var appElement: AXUIElement?
    @ObservationIgnored private var pid: pid_t = 0
    @ObservationIgnored private var seen: [String] = []          // recent banner ids (bounded)
    @ObservationIgnored private var banners: [String: AXUIElement] = [:]
    @ObservationIgnored private var scanScheduled = false
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    private static let ncBundleID = "com.apple.notificationcenterui"

    func refresh() {
        let prefs = Preferences.shared
        if prefs.mirrorNotifications, !prefs.mirroredApps.isEmpty, AXIsProcessTrusted() { start() } else { stop() }
    }

    private func start() {
        if launchObserver == nil {
            // Notification Center can restart; re-attach to the new process.
            launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated { if id == Self.ncBundleID { self?.attach() } }
            }
        }
        attach()
    }

    private func stop() {
        detach()
        if let launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(launchObserver) }
        launchObserver = nil
    }

    private func attach() {
        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: Self.ncBundleID).first else { return }
        if observer != nil, nc.processIdentifier == pid { return }
        detach()
        pid = nc.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<NotificationMirrorService>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.scheduleScan() }
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        log.info("watching Notification Center (pid \(self.pid, privacy: .public))")
        observer = obs
        appElement = app
        // Whatever is on screen right now is old news.
        for banner in currentBanners() { remember(banner.id) }
    }

    private func detach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        appElement = nil
        pid = 0
        banners.removeAll()
    }

    // MARK: Scanning

    /// AX notifications arrive in bursts per banner; scan once per burst.
    private func scheduleScan() {
        guard !scanScheduled else { return }
        scanScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.scanScheduled = false
            self.scan()
        }
    }

    private func scan() {
        let fresh = currentBanners().filter { !seen.contains($0.id) }
        fresh.forEach { remember($0.id) }
        // Several "new" banners at once means the Notification Center list was opened.
        guard fresh.count <= 2 else { return }
        let prefs = Preferences.shared
        let wanted = Set(prefs.mirroredApps.map { $0.lowercased() })
        for banner in fresh where wanted.contains(banner.note.app.lowercased()) {
            banners[banner.id] = banner.element
            if banners.count > 20, let oldest = banners.keys.first { banners[oldest] = nil }
            var note = banner.note
            if prefs.hideNotificationText {
                note = MirroredNotification(id: note.id, app: note.app, title: note.title, subtitle: nil,
                                            body: String(localized: "New notification"))
            }
            log.info("mirrored a notification from \(note.app, privacy: .public)")
            ActivityCenter.shared.show(.appNotification(note))
            SoundService.shared.play(.appNotification)
        }
    }

    private func remember(_ id: String) {
        seen.append(id)
        if seen.count > 120 { seen.removeFirst(seen.count - 120) }
    }

    private func currentBanners() -> [(id: String, note: MirroredNotification, element: AXUIElement)] {
        guard let appElement else { return [] }
        var result: [(String, MirroredNotification, AXUIElement)] = []
        for window in Self.children(appElement, kAXWindowsAttribute) {
            Self.findBanners(window, depth: 0, into: &result)
        }
        return result.map { (id: $0.0, note: $0.1, element: $0.2) }
    }

    private static func findBanners(_ e: AXUIElement, depth: Int, into out: inout [(String, MirroredNotification, AXUIElement)]) {
        guard depth < 8 else { return }
        if string(e, kAXSubroleAttribute) == "AXNotificationCenterBanner" {
            if let note = parse(e) { out.append((note.id, note, e)) }
            return
        }
        for child in children(e, kAXChildrenAttribute) { findBanners(child, depth: depth + 1, into: &out) }
    }

    /// Banner: description "App, Title, Subtitle, Body" + static texts identified title/subtitle/body.
    private static func parse(_ banner: AXUIElement) -> MirroredNotification? {
        let id = string(banner, kAXIdentifierAttribute) ?? string(banner, kAXDescriptionAttribute) ?? ""
        var title = "", subtitle: String?, body: String?
        for text in children(banner, kAXChildrenAttribute) {
            let value = string(text, kAXValueAttribute)
            switch string(text, kAXIdentifierAttribute) {
            case "title": title = value ?? ""
            case "subtitle": subtitle = value
            case "body": body = value
            default: break
            }
        }
        let description = string(banner, kAXDescriptionAttribute) ?? ""
        let parts = [title, subtitle, body].compactMap { $0 }.filter { !$0.isEmpty }
        var app = description
        if let first = parts.first, let range = description.range(of: ", " + first) {
            app = String(description[..<range.lowerBound])
        } else if let comma = description.firstIndex(of: ",") {
            app = String(description[..<comma])
        }
        guard !id.isEmpty, !app.isEmpty, !(title.isEmpty && (body ?? "").isEmpty) else { return nil }
        return MirroredNotification(id: id, app: app, title: title.isEmpty ? app : title, subtitle: subtitle, body: body)
    }

    // MARK: Actions

    /// Opens what the notification points at (e.g. that Slack channel), like clicking the banner.
    func open(_ note: MirroredNotification) {
        if let banner = banners[note.id], AXUIElementPerformAction(banner, kAXPressAction as CFString) == .success {
            ActivityCenter.shared.dismiss()
            return
        }
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == note.app }) {
            app.activate()
        }
        ActivityCenter.shared.dismiss()
    }

    static func icon(for appName: String) -> NSImage? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else { return nil }
        return app.icon
    }

    // MARK: AX helpers

    private static func string(_ e: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return nil }
        return (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func children(_ e: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
