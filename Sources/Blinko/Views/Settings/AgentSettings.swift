import AppKit
import BlinkoKit
import SwiftUI

// MARK: - Agents

struct AgentsSettingsPane: View {
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        @Bindable var p = Preferences.shared
        let hub = AgentHubService.shared
        Form {
            Section {
                Toggle("Agent Hub", isOn: $p.agentHubEnabled)
                if p.agentHubEnabled {
                    if let failure = hub.lastError {
                        Label("Couldn't open the socket: \(failure)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Label("Listening for agents", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } footer: {
                Text("Coding agents report their status to Blinko over a private socket on this Mac (readable by your user only). Nothing received is ever executed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: "asterisk")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.agentAccent.gradient))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Claude Code")
                        Text(hub.claudeHooksInstalled ? "Connected through hooks" : "Not connected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if hub.claudeHooksInstalled {
                        Button("Disconnect") { run { try hub.uninstallClaudeHooks() } }
                    } else {
                        Button("Connect Claude Code") { run { try hub.installClaudeHooks() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(busy)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout)
                }
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Adds Blinko's hooks to ~/.claude/settings.json (your other hooks and settings are kept; the previous file is saved as settings.json.blinko-backup). Disconnect removes only Blinko's entries. Sessions started before connecting appear after their next restart.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Approve or deny permission requests in the island", isOn: $p.agentApprovals)
                Toggle("Open the island when an agent asks", isOn: $p.agentAutoOpen)
                    .disabled(!p.agentApprovals)
                Picker("Wait for an answer", selection: $p.agentApprovalTimeout) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("90 seconds").tag(90.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                }
                .disabled(!p.agentApprovals)
            } header: {
                Text("Approvals")
            } footer: {
                Text("Click the approval card to answer with ⌘↩ (approve) or esc (deny). If you don't answer in time, or Blinko isn't running, the agent asks in its own window as usual.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("In the closed island") {
                Toggle("Show agent activity", isOn: $p.agentCompact)
                Toggle("“Finished” when a long task ends", isOn: $p.agentFinishedAlert)
                Toggle("Agent notifications", isOn: $p.agentNotifications)
                Toggle("Agents tab", isOn: Binding(
                    get: { !p.hiddenTabs.contains(.agents) },
                    set: { visible in
                        if visible { p.hiddenTabs.remove(.agents) } else if p.visibleTabs.count > 1 { p.hiddenTabs.insert(.agents) }
                    }))
            }

            Section {
                LabeledContent("Socket") {
                    HStack(spacing: 6) {
                        Text(verbatim: AgentProtocol.socketPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        CopyButton(text: AgentProtocol.socketPath)
                    }
                }
            } header: {
                Text("Other agents")
            } footer: {
                Text("Codex, Cursor or your own scripts can report sessions and ask for approvals with the same newline-delimited JSON protocol (docs/AGENT_PROTOCOL.md), e.g. by piping lines into “blinko send”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { hub.checkHooks() }
    }

    private func run(_ action: @escaping () throws -> Void) {
        busy = true
        defer { busy = false }
        do {
            try action()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Automation

struct AutomationSettingsPane: View {
    @State private var linkPath = CLIInstaller.installedLink()
    @State private var error: String?

    private static let examples: [(String, String)] = [
        ("blinko://alert?title=Build%20passed&icon=checkmark.seal.fill&color=green", "Custom alert"),
        ("blinko://timer?minutes=25&label=Deep%20work", "Start a timer"),
        ("blinko://focus/start", "Start a focus session"),
        ("blinko://open?tab=shelf", "Open a tab"),
        ("blinko://shelf/add?path=~/Desktop/report.pdf", "Add a file to the shelf"),
        ("blinko://keepawake?minutes=60", "Keep awake (off=1 stops)"),
    ]

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "blinko")
                            .font(.system(.body, design: .monospaced))
                        if let linkPath {
                            Text("Installed at \(linkPath)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Not installed").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if linkPath != nil {
                        Button("Remove") { act { try CLIInstaller.uninstall() } }
                    } else {
                        Button("Install Command-Line Tool") { act { try CLIInstaller.install() } }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                }
                if let linkPath, linkPath.hasPrefix(NSHomeDirectory()) {
                    Text("Make sure ~/.local/bin is on your PATH (e.g. add export PATH=\"$HOME/.local/bin:$PATH\" to ~/.zshrc).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Command-line tool")
            } footer: {
                Text("Links the blinko tool from inside Blinko.app into /usr/local/bin when it is writable, otherwise ~/.local/bin. No administrator password is used. Try: blinko alert \"Deploy done\" --icon checkmark.circle.fill --color green")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(Self.examples, id: \.0) { url, title in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LocalizedStringKey(title))
                            Text(verbatim: url.removingPercentEncoding ?? url)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                        Spacer()
                        CopyButton(text: url)
                    }
                }
                Button("Send a Test Alert") {
                    URLSchemeHandler.perform(URL(string: "blinko://alert?title=Hello%20from%20Blinko&icon=sparkles&color=pink")!)
                }
            } header: {
                Text("URL scheme")
            } footer: {
                Text("In Shortcuts, use “Open URLs” with a blinko:// link, or “Run Shell Script” with the blinko tool. alert also takes body, color (a name or #RRGGBB) and duration (seconds).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func act(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        linkPath = CLIInstaller.installedLink()
    }
}

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? .green : .secondary)
                .frame(width: 16)
        }
        .buttonStyle(.plain)
        .help("Copy")
    }
}

/// Symlinks Contents/Helpers/blinko onto the PATH. Never escalates privileges.
@MainActor
enum CLIInstaller {
    static var candidates: [String] {
        ["/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
    }

    /// Path of an existing link that points into a Blinko bundle.
    static func installedLink() -> String? {
        let fm = FileManager.default
        for dir in candidates {
            let link = dir + "/blinko"
            if let dest = try? fm.destinationOfSymbolicLink(atPath: link), dest.hasSuffix("Contents/Helpers/blinko") {
                return link
            }
        }
        return nil
    }

    static func install() throws {
        let fm = FileManager.default
        let target = AgentHubService.bundledCLI.path
        guard fm.isExecutableFile(atPath: target) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "The blinko tool is missing from the app bundle. Build Blinko with scripts/build.sh.")])
        }
        let system = candidates[0]
        let dir = fm.isWritableFile(atPath: system) ? system : candidates[1]
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let link = dir + "/blinko"
        if (try? fm.destinationOfSymbolicLink(atPath: link)) != nil || fm.fileExists(atPath: link) {
            // Only replace our own link, never someone else's file.
            guard let dest = try? fm.destinationOfSymbolicLink(atPath: link), dest.hasSuffix("Contents/Helpers/blinko") else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSLocalizedDescriptionKey:
                    String(localized: "\(link) already exists and isn't Blinko's. Remove it first.")])
            }
            try fm.removeItem(atPath: link)
        }
        try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
    }

    static func uninstall() throws {
        guard let link = installedLink() else { return }
        try FileManager.default.removeItem(atPath: link)
    }
}
