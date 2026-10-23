import AppKit
import SwiftUI

/// Settings search. Entries are generated from the Settings source by
/// scripts/gen-settings-index.py (run by build.sh), so every control is findable.
enum SettingsSearch {
    struct Entry: Identifiable, Hashable {
        let title: String
        let pane: SettingsPane
        let section: String
        var id: String { pane.rawValue + "|" + title }
        var localizedTitle: String { String(localized: String.LocalizationValue(title)) }
        var localizedSection: String { section.isEmpty ? "" : String(localized: String.LocalizationValue(section)) }
    }

    /// Everyday words people search for that don't appear in a control's label.
    private static let synonyms: [(trigger: String, words: String)] = [
        ("hud", "volume brightness keyboard backlight osd popup sound"),
        ("volume", "sound speaker audio"),
        ("weather", "temperature forecast rain sun"),
        ("now playing", "music song spotify apple music media player"),
        ("music", "song spotify media player"),
        ("visualizer", "bars equalizer spectrum music"),
        ("lyrics", "karaoke words song"),
        ("shelf", "files drop drag airdrop tray"),
        ("clipboard", "copy paste history"),
        ("launch at login", "startup start boot automatically open"),
        ("shortcut", "hotkey keyboard key combo"),
        ("calendar", "events meetings reminders agenda schedule"),
        ("focus", "pomodoro do not disturb dnd concentrate"),
        ("battery", "charging power low"),
        ("bluetooth", "airpods headphones earbuds devices"),
        ("haptic", "vibration feedback trackpad"),
        ("hover", "mouse pointer cursor open"),
        ("gesture", "swipe trackpad"),
        ("keep awake", "caffeinate sleep display"),
        ("mirror", "camera webcam"),
        ("clock", "time world timezone date"),
        ("menu bar", "status icon tray"),
        ("fullscreen", "full screen games video hide"),
        ("display", "screen monitor external"),
        ("accent", "color colour theme"),
        ("style", "theme look appearance glass glow minimal"),
        ("credit", "optimageeks designed by footer"),
        ("update", "sparkle version upgrade"),
        ("agent", "claude code ai codex approvals"),
        ("meeting", "zoom teams meet call mute"),
        ("command", "spotlight launcher calculator search"),
        ("download", "progress files safari chrome"),
        ("network", "wifi wi-fi vpn hotspot internet"),
        ("privacy", "camera microphone mic indicator"),
        ("notes", "scratchpad snippets"),
        ("color picker", "eyedropper hex rgb"),
        ("timer", "countdown stopwatch alarm"),
        ("lock screen", "locked login"),
        ("language", "translation localization urdu spanish"),
        ("sound", "audio chime tone alert notification beep ding"),
        ("notifications", "slack messages whatsapp teams discord banner mirror dm"),
        ("timer", "countdown alarm"),
        ("permission", "approve approval claude agent"),
    ]

    /// Generated entries plus the per-event sound switches (built at runtime, so not in the scan).
    static var entries: [Entry] {
        generatedEntries + SoundEvent.allCases.map { Entry(title: $0.title, pane: .sounds, section: $0.group) }
    }

    /// All query words must match the title, section, pane or a synonym; title hits rank first.
    static func search(_ query: String) -> [Entry] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var scored: [(Entry, Int)] = []
        for entry in entries {
            let title = (entry.localizedTitle + " " + entry.title).lowercased()
            let context = (entry.localizedSection + " " + entry.section + " " + entry.pane.title).lowercased()
            let extra = synonyms.filter { title.contains($0.trigger) || context.contains($0.trigger) }
                .map(\.words).joined(separator: " ")
            var score = 0
            var matchedAll = true
            for w in words {
                if title.hasPrefix(w) { score += 4 }
                else if title.contains(w) { score += 3 }
                else if extra.contains(w) { score += 2 }
                else if context.contains(w) { score += 1 }
                else { matchedAll = false; break }
            }
            if matchedAll { scored.append((entry, score)) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title.count < $1.0.title.count }
            .prefix(40).map(\.0)
    }
}

/// Scrolls a Settings control into view and flashes an accent outline around it. Finds the
/// control through the window's accessibility tree, so panes need no per-row markup.
@MainActor
enum SettingsHighlighter {
    static func reveal(_ title: String, in window: NSWindow?, attempt: Int = 0) {
        guard let window, let root = window.contentView else { return }
        guard let element = find(title, in: root, depth: 0) else {
            if attempt < 4 {   // the pane may still be building
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { reveal(title, in: window, attempt: attempt + 1) }
            }
            return
        }
        var frame = element.accessibilityFrame()
        if let scroll = enclosingScrollView(for: frame, in: root, window: window),
           let document = scroll.documentView {
            let inWindow = window.convertFromScreen(frame)
            let inDocument = document.convert(inWindow, from: nil)
            document.scrollToVisible(inDocument.insetBy(dx: 0, dy: -60))
            frame = element.accessibilityFrame()
        }
        flash(window.convertFromScreen(frame), in: root)
    }

    private static func find(_ title: String, in node: Any, depth: Int) -> NSAccessibilityProtocol? {
        guard depth < 40, let element = node as? NSAccessibilityProtocol else { return nil }
        let label = element.accessibilityLabel() ?? ""
        let elementTitle = (element as? NSAccessibilityElementProtocol & NSObjectProtocol)
            .flatMap { ($0 as? NSView)?.accessibilityTitle() ?? ($0 as? NSAccessibilityElement)?.accessibilityTitle() } ?? ""
        let wanted = String(localized: String.LocalizationValue(title))
        if [label, elementTitle].contains(where: { $0 == wanted || $0 == title }),
           element.accessibilityFrame().height > 4 {
            return element
        }
        for child in element.accessibilityChildren() ?? [] {
            if let hit = find(title, in: child, depth: depth + 1) { return hit }
        }
        return nil
    }

    private static func enclosingScrollView(for screenFrame: NSRect, in view: NSView, window: NSWindow) -> NSScrollView? {
        let point = window.convertFromScreen(screenFrame).origin
        var best: NSScrollView?
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView, s.convert(s.bounds, to: nil).insetBy(dx: 0, dy: -4000).contains(point),
               best == nil || s.bounds.height > best!.bounds.height {
                best = s
            }
            v.subviews.forEach(walk)
        }
        walk(view)
        return best
    }

    private static func flash(_ windowRect: NSRect, in root: NSView) {
        let rect = root.convert(windowRect, from: nil).insetBy(dx: -6, dy: -4)
        let ring = NSView(frame: rect)
        ring.wantsLayer = true
        ring.layer?.cornerRadius = 8
        ring.layer?.borderWidth = 2
        ring.layer?.borderColor = NSColor.controlAccentColor.cgColor
        ring.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        root.addSubview(ring)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.allowsImplicitAnimation = true
            ring.animator().alphaValue = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.5
                    ring.animator().alphaValue = 0
                }, completionHandler: { ring.removeFromSuperview() })
            }
        })
    }
}

/// Sidebar results list shown while a query is typed.
struct SettingsSearchResults: View {
    let query: String
    let onPick: (SettingsSearch.Entry) -> Void

    var body: some View {
        let results = SettingsSearch.search(query)
        List {
            if results.isEmpty {
                Text("No settings match “\(query)”")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ForEach(results) { entry in
                Button { onPick(entry) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: entry.pane.symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(entry.pane.tint.gradient))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.localizedTitle).lineLimit(2)
                            Text(entry.section.isEmpty ? entry.pane.title : "\(entry.pane.title) › \(entry.localizedSection)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
