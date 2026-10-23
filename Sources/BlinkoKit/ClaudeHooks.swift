import Foundation

/// Claude Code integration: maps hook input (stdin JSON) to Agent Hub messages, and adds or
/// removes Blinko's hooks in `~/.claude/settings.json` without touching anything else.
public enum ClaudeHooks {
    public static let agentID = "claude-code"

    /// Hook events Blinko listens to. `matcher` is set for tool events (all tools).
    public static let events: [(name: String, toolEvent: Bool)] = [
        ("SessionStart", false), ("UserPromptSubmit", false), ("PreToolUse", true), ("PostToolUse", true),
        ("PermissionRequest", true), ("Notification", false), ("Stop", false), ("SubagentStop", false),
        ("SessionEnd", false),
    ]

    /// Seconds Claude Code allows a hook. Status hooks return in milliseconds; the permission
    /// hook may wait for a decision in the island (Blinko answers "ask" well before this).
    static func timeout(for event: String) -> Int { event == "PermissionRequest" ? 600 : 10 }

    /// `~/.claude/settings.json` (honours `CLAUDE_CONFIG_DIR`).
    public static var defaultSettingsURL: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("settings.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Every Blinko hook command contains this, which is how uninstall finds them.
    static let marker = "Blinko/bin/blinko"

    public static func command(helperPath: String) -> String {
        "\"\(helperPath)\" hook"
    }

    // MARK: Installer

    public enum InstallError: LocalizedError {
        case unreadable(String)
        case notAnObject

        public var errorDescription: String? {
            switch self {
            case .unreadable(let why): "settings.json could not be read as JSON (\(why)). Nothing was changed."
            case .notAnObject: "settings.json does not contain a JSON object. Nothing was changed."
            }
        }
    }

    /// Whether every Blinko hook is present.
    public static func isInstalled(settingsURL: URL = defaultSettingsURL) -> Bool {
        guard let root = try? readSettings(settingsURL), let hooks = root["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event.name] as? [Any])?.contains(where: isBlinkoGroup) ?? false
        }
    }

    /// read → back up to `settings.json.blinko-backup` → merge (existing hooks kept, earlier
    /// Blinko entries replaced) → atomic write.
    public static func install(settingsURL: URL = defaultSettingsURL, helperPath: String) throws {
        var root = try readSettings(settingsURL)
        try backUp(settingsURL, current: root)
        var hooks = removingBlinko(from: root["hooks"] as? [String: Any] ?? [:])
        let cmd = command(helperPath: helperPath)
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": cmd, "timeout": timeout(for: event.name)]]]
            if event.toolEvent { group["matcher"] = "*" }
            var groups = hooks[event.name] as? [Any] ?? []
            groups.append(group)
            hooks[event.name] = groups
        }
        root["hooks"] = hooks
        try write(root, to: settingsURL)
    }

    /// Removes only Blinko's entries; empty groups / events / `hooks` left behind are dropped.
    public static func uninstall(settingsURL: URL = defaultSettingsURL) throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var root = try readSettings(settingsURL)
        guard let hooks = root["hooks"] as? [String: Any] else { return }
        try backUp(settingsURL, current: root)
        let cleaned = removingBlinko(from: hooks)
        if cleaned.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = cleaned }
        try write(root, to: settingsURL)
    }

    static func readSettings(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw InstallError.unreadable(error.localizedDescription) }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch { throw InstallError.unreadable("invalid JSON") }
        guard let dict = object as? [String: Any] else { throw InstallError.notAnObject }
        return dict
    }

    /// The backup keeps the last state *without* Blinko's hooks: it is refreshed only when the
    /// current file has none (or there is no backup yet), so reinstalling never overwrites it
    /// with a copy that already contains them.
    private static func backUp(_ url: URL, current root: [String: Any]) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let backup = url.appendingPathExtension("blinko-backup")
        let hasBlinko = (root["hooks"] as? [String: Any])?.values.contains { ($0 as? [Any])?.contains(where: isBlinkoGroup) ?? false } ?? false
        if fm.fileExists(atPath: backup.path) {
            guard !hasBlinko else { return }
            try fm.removeItem(at: backup)
        }
        try fm.copyItem(at: url, to: backup)
    }

    private static func write(_ root: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private static func isBlinkoHook(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains(marker) ?? false
    }

    private static func isBlinkoGroup(_ group: Any) -> Bool {
        ((group as? [String: Any])?["hooks"] as? [Any])?.contains(where: isBlinkoHook) ?? false
    }

    private static func removingBlinko(from hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept: [Any] = groups.compactMap { group in
                guard var dict = group as? [String: Any], let inner = dict["hooks"] as? [Any] else { return group }
                let remaining = inner.filter { !isBlinkoHook($0) }
                if remaining.count == inner.count { return group }
                if remaining.isEmpty { return nil }
                dict["hooks"] = remaining
                return dict
            }
            if kept.isEmpty { result.removeValue(forKey: event) } else { result[event] = kept }
        }
        return result
    }

    // MARK: Hook input → protocol

    /// Translates one Claude Code hook invocation. nil = nothing to report.
    public static func message(fromHookInput input: [String: Any]) -> AgentMessage? {
        guard let event = input["hook_event_name"] as? String,
              let session = input["session_id"] as? String else { return nil }
        let cwd = input["cwd"] as? String
        var msg = AgentMessage(type: AgentMessage.Kind.status, session: session, agent: agentID, cwd: cwd)
        let tool = input["tool_name"] as? String
        let toolInput = input["tool_input"] as? [String: Any] ?? [:]

        switch event {
        case "SessionStart":
            msg.type = AgentMessage.Kind.sessionStart
            msg.state = "idle"
            msg.title = (input["session_title"] as? String).flatMap { $0.isEmpty ? nil : $0.agentClipped(60) }
        case "UserPromptSubmit":
            msg.state = "working"
            msg.detail = (input["prompt"] as? String)?.agentClipped(90)
        case "PreToolUse":
            msg.type = AgentMessage.Kind.tool
            msg.phase = "start"
            msg.tool = tool
            msg.summary = summary(tool: tool, input: toolInput)
        case "PostToolUse":
            msg.type = AgentMessage.Kind.tool
            msg.phase = "end"
            msg.tool = tool
            msg.summary = summary(tool: tool, input: toolInput)
        case "PermissionRequest":
            msg.type = AgentMessage.Kind.permissionRequest
            msg.id = UUID().uuidString
            msg.tool = tool
            msg.summary = summary(tool: tool, input: toolInput)
            msg.detail = detail(tool: tool, input: toolInput)
        case "Notification":
            let kind = input["notification_type"] as? String
            // The approval itself arrives as PermissionRequest.
            if kind == "permission_prompt" { return nil }
            let text = (input["message"] as? String)?.agentClipped(120)
            if kind == "idle_prompt" {
                msg.state = "idle"
                msg.detail = text
            } else {
                msg.type = AgentMessage.Kind.notification
                msg.message = text
            }
        case "Stop":
            msg.state = "idle"
            msg.detail = (input["last_assistant_message"] as? String)?.agentClipped(120)
        case "SubagentStop":
            msg.type = AgentMessage.Kind.tool
            msg.phase = "end"
            msg.tool = "Agent"
            msg.summary = (input["agent_type"] as? String).map { "\($0) finished" } ?? "Subagent finished"
        case "SessionEnd":
            msg.type = AgentMessage.Kind.sessionEnd
        default:
            return nil
        }
        return msg
    }

    /// One line describing what a tool is about to do: the command, the file, the pattern…
    public static func summary(tool: String?, input: [String: Any]) -> String? {
        func s(_ key: String) -> String? { (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let raw: String?
        switch tool ?? "" {
        case "Bash": raw = s("command")
        case "Read", "Write", "Edit", "MultiEdit": raw = s("file_path").map(shortPath)
        case "NotebookEdit": raw = s("notebook_path").map(shortPath)
        case "Grep", "Glob": raw = s("pattern")
        case "WebFetch": raw = s("url")
        case "WebSearch": raw = s("query")
        case "Task", "Agent": raw = s("description")
        default:
            raw = ["command", "file_path", "path", "url", "query", "description", "prompt"].lazy.compactMap(s).first
                ?? input.values.lazy.compactMap { $0 as? String }.first
        }
        return raw?.agentClipped(200)
    }

    /// Extra context for an approval card (e.g. Bash's description, an edit's old → new size).
    static func detail(tool: String?, input: [String: Any]) -> String? {
        switch tool ?? "" {
        case "Bash": return (input["description"] as? String)?.agentClipped(140)
        case "Write": return (input["content"] as? String).map { "\($0.split(separator: "\n", omittingEmptySubsequences: false).count) lines" }
        case "Edit":
            guard let old = input["old_string"] as? String, let new = input["new_string"] as? String else { return nil }
            func lines(_ s: String) -> Int { s.isEmpty ? 0 : s.split(separator: "\n", omittingEmptySubsequences: false).count }
            return "−\(lines(old)) +\(lines(new)) lines"
        default: return nil
        }
    }

    private static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: Decision → hook output

    /// stdout for a PermissionRequest hook; nil = print nothing (Claude Code shows its own prompt).
    public static func hookOutput(for response: AgentMessage) -> Data? {
        let decision: [String: Any]
        switch response.decision {
        case "allow": decision = ["behavior": "allow"]
        case "deny": decision = ["behavior": "deny", "message": response.reason ?? "Denied in Blinko"]
        default: return nil
        }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    }
}

public enum HookHelper {
    /// Copies the CLI to the stable path hooks call, when missing or different. Returns true if it changed.
    @discardableResult
    public static func install(from source: URL, to path: String = AgentProtocol.hookHelperPath) throws -> Bool {
        let fm = FileManager.default
        let dest = URL(fileURLWithPath: path)
        let src = source.resolvingSymlinksInPath()
        guard src.path != dest.resolvingSymlinksInPath().path else { return false }
        if let a = fm.contents(atPath: src.path), let b = fm.contents(atPath: dest.path), a == b { return false }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let temp = dest.deletingLastPathComponent().appendingPathComponent(".blinko-\(UUID().uuidString)")
        try fm.copyItem(at: src, to: temp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
        // rename(2) is atomic: a hook running right now keeps the old inode.
        guard rename(temp.path, dest.path) == 0 else {
            try? fm.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
        return true
    }
}
