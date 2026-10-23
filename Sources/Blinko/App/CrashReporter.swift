import AppKit
import SwiftUI

/// Feedback and crash reports, privacy-first: nothing is ever sent by Blinko. Both open a
/// pre-filled GitHub issue in the browser, where the user reads (and edits) every word before
/// deciding to submit it. No SDK, no telemetry, no network request from the app.
enum Feedback {
    static let repository = "https://github.com/techInnovator1999/Blinko"

    enum Kind { case bug, feature }

    static func open(_ kind: Kind) {
        switch kind {
        case .bug:
            openIssue(title: "", labels: "bug", body: """
            **What happened?**


            **What did you expect instead?**


            **Steps to reproduce**
            1.

            **Environment**
            \(environment)
            """)
        case .feature:
            openIssue(title: "", labels: "enhancement", body: """
            **What would you like Blinko to do?**


            **How would it help you?**


            **Anything else?** (screenshots, apps that do it well)


            \(environment)
            """)
        }
    }

    static func openIssue(title: String, labels: String, body: String) {
        if let url = issueURL(title: title, labels: labels, body: body) { NSWorkspace.shared.open(url) }
    }

    static func issueURL(title: String, labels: String, body: String) -> URL? {
        var c = URLComponents(string: repository + "/issues/new")
        c?.queryItems = [URLQueryItem(name: "title", value: title),
                         URLQueryItem(name: "labels", value: labels),
                         URLQueryItem(name: "body", value: body)]
        // URLComponents leaves "+" alone, which GitHub would read as a space.
        let query = c?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        c?.percentEncodedQuery = query
        return c?.url
    }

    /// Version, macOS and Mac model: what a bug report needs, nothing that identifies the user.
    static var environment: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osBuild = sysctlString("kern.osversion").map { " (\($0))" } ?? ""
        #if arch(arm64)
        let arch = "Apple silicon"
        #else
        let arch = "Intel"
        #endif
        return """
        - Blinko \(version) (\(build))
        - macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\(osBuild)
        - Mac: \(sysctlString("hw.model") ?? "unknown") (\(arch))
        - Language: \(Locale.preferredLanguages.first ?? "?")
        """
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}

/// Looks once per launch for crash reports macOS wrote for Blinko since the last check
/// (`~/Library/Logs/DiagnosticReports/Blinko-*.ips`) and, if there is a new one, offers —
/// once, in a small non-modal panel — to open a pre-filled issue with the redacted crash.
@MainActor
enum CrashReporter {
    private static let checkKey = "crashReportsCheckedAt"
    private static var panel: NSPanel?

    nonisolated static var reportsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// Called at launch: a short delay, then one directory listing off the main thread.
    static func checkOnLaunch() {
        let defaults = UserDefaults.standard
        // First run of a version with this check: look back a few days, not forever.
        let since = defaults.object(forKey: checkKey) as? Date ?? Date().addingTimeInterval(-3 * 86_400)
        defaults.set(Date(), forKey: checkKey)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) {
            guard let newest = newestReport(in: reportsDirectory, since: since),
                  let summary = CrashSummary(contentsOf: newest) else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { offer(summary) } }
        }
    }

    nonisolated static func newestReport(in directory: URL, since: Date) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return nil }
        return files
            .filter { $0.lastPathComponent.hasPrefix("Blinko-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate, date > since else { return nil }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?.0
    }

    private static func offer(_ summary: CrashSummary) {
        guard panel == nil else { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.hidesOnDeactivate = false
        p.title = String(localized: "Crash report")
        let close = {
            panel?.close()
            panel = nil
        }
        p.contentView = NSHostingView(rootView: CrashPromptView(review: {
            Feedback.openIssue(title: summary.issueTitle, labels: "bug,crash", body: summary.issueBody)
            close()
        }, dismiss: close))
        p.setContentSize(p.contentView!.fittingSize)
        // Top-right, where notifications appear: noticeable, never in the way.
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameTopLeftPoint(NSPoint(x: f.maxX - p.frame.width - 16, y: f.maxY - 12))
        }
        p.orderFrontRegardless()
        panel = p
    }

    /// `Blinko --crash-report <file.ips>` prints the issue Blinko would pre-fill (design QA).
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--crash-report"), i + 1 < args.count else { return false }
        let url = URL(fileURLWithPath: args[i + 1])
        guard let summary = CrashSummary(contentsOf: url) else { print("not a readable crash report:", url.path); return true }
        print("TITLE:", summary.issueTitle)
        print(summary.issueBody)
        let link = Feedback.issueURL(title: summary.issueTitle, labels: "bug,crash", body: summary.issueBody)
        print("URL length:", link?.absoluteString.count ?? 0)
        return true
    }
}

struct CrashPromptView: View {
    let review: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AppIconView(size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Blinko quit unexpectedly last time")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Send a crash report? It opens a pre-filled GitHub issue in your browser so you can review it first. Nothing is sent automatically.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Not Now", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("Review Report…", action: review)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .frame(width: 380)
    }
}

/// The parts of a macOS `.ips` crash report worth putting in an issue, with every trace of
/// the user's name and home folder removed.
struct CrashSummary {
    let date: Date
    let appVersion: String
    let osVersion: String
    let model: String
    let exception: String
    let termination: String?
    let message: String?
    let threadIndex: Int
    let frames: [String]

    /// Parses the two-part `.ips` format: one JSON header line, then the JSON report.
    init?(contentsOf url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let newline = text.firstIndex(of: "\n") else { return nil }
        let headerData = Data(text[..<newline].utf8)
        let bodyData = Data(text[text.index(after: newline)...].utf8)
        guard let header = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any],
              let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        date = modified ?? Date()
        let version = header["app_version"] as? String ?? ""
        let build = header["build_version"] as? String ?? ""
        appVersion = version.isEmpty ? "unknown (development build)" : (build.isEmpty ? version : "\(version) (\(build))")
        osVersion = header["os_version"] as? String ?? "unknown"
        model = body["modelCode"] as? String ?? "unknown"

        let ex = body["exception"] as? [String: Any] ?? [:]
        var exception = ex["type"] as? String ?? "unknown"
        if let signal = ex["signal"] as? String { exception += " (\(signal))" }
        if let subtype = ex["subtype"] as? String { exception += " · \(subtype)" }
        self.exception = Self.redact(exception)

        if let t = body["termination"] as? [String: Any] {
            let parts = [t["namespace"] as? String, t["indicator"] as? String,
                         (t["reasons"] as? [String])?.first ?? (t["details"] as? [String])?.first]
            termination = Self.redact(Self.clip(parts.compactMap { $0 }.joined(separator: " — "), 400))
        } else {
            termination = nil
        }
        // Application-specific info: Swift's "Fatal error: …" message lives here.
        if let asi = body["asi"] as? [String: [String]] {
            let lines = asi.values.flatMap { $0 }.joined(separator: "\n")
            message = lines.isEmpty ? nil : Self.redact(Self.clip(lines, 500))
        } else {
            message = nil
        }

        let images = (body["usedImages"] as? [[String: Any]]) ?? []
        let threads = (body["threads"] as? [[String: Any]]) ?? []
        let faulting = body["faultingThread"] as? Int ?? threads.firstIndex { ($0["triggered"] as? Bool) == true } ?? 0
        threadIndex = faulting
        let frames = threads.indices.contains(faulting) ? (threads[faulting]["frames"] as? [[String: Any]] ?? []) : []
        self.frames = frames.prefix(14).enumerated().map { i, frame in
            let imageIndex = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(imageIndex) ? (images[imageIndex]["name"] as? String ?? "???") : "???"
            var line = "\(i)".padding(toLength: 3, withPad: " ", startingAt: 0) + image.padding(toLength: 24, withPad: " ", startingAt: 0)
            if let symbol = frame["symbol"] as? String {
                line += " " + Self.clip(symbol, 160)
                if let offset = frame["symbolLocation"] as? Int { line += " + \(offset)" }
            } else if let offset = frame["imageOffset"] as? Int {
                line += String(format: " 0x%llx", offset)
            }
            if let file = frame["sourceFile"] as? String {
                line += " (\((file as NSString).lastPathComponent)"
                if let l = frame["sourceLine"] as? Int { line += ":\(l)" }
                line += ")"
            }
            return Self.redact(line)
        }
    }

    var issueTitle: String {
        "Crash: \(exception)" + (firstAppFrame.map { " in \($0)" } ?? "")
    }

    /// The topmost frame inside Blinko itself, which usually names the culprit.
    private var firstAppFrame: String? {
        frames.lazy.compactMap { line -> String? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count > 2, parts[1] == "Blinko" else { return nil }
            return String(parts[2])
        }.first.map { Self.clip($0, 80) }
    }

    var issueBody: String {
        var crash = "Exception: \(exception)\n"
        if let termination { crash += "Termination: \(termination)\n" }
        if let message { crash += "Message: \(message)\n" }
        crash += "Faulting thread \(threadIndex):\n" + frames.joined(separator: "\n")
        return """
        **What were you doing when Blinko quit?** (optional)


        **Environment**
        - Blinko \(appVersion)
        - \(osVersion)
        - Mac: \(model)

        **Crash report** (from ~/Library/Logs/DiagnosticReports, \(date.formatted(date: .abbreviated, time: .shortened)); user name and paths removed)
        ```
        \(crash)
        ```
        """
    }

    private static func clip(_ s: String, _ n: Int) -> String {
        s.count > n ? String(s.prefix(n)) + "…" : s
    }

    /// Removes the home folder, any /Users/<name> path and the user's account and full name.
    static func redact(_ s: String) -> String {
        var out = s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        out = out.replacingOccurrences(of: #"/Users/[^/\s'"]+"#, with: "/Users/USER", options: .regularExpression)
        for name in [NSUserName(), NSFullUserName()] where name.count >= 3 {
            out = out.replacingOccurrences(of: name, with: "USER", options: .caseInsensitive)
        }
        return out
    }
}
