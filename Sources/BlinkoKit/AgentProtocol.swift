import Foundation

/// Agent Hub wire protocol (v1): newline-delimited JSON over a Unix domain socket owned by
/// Blinko. Documented in docs/AGENT_PROTOCOL.md. Shared by the app and the `blinko` CLI.
public enum AgentProtocol {
    public static let version = 1
    /// Longest accepted line; longer input closes the connection.
    public static let maxLineBytes = 256 * 1024
    /// Hard cap a client waits for a permission decision (Blinko's own, shorter timeout applies first).
    public static let maxApprovalWait: TimeInterval = 590

    /// ~/Library/Application Support/Blinko
    public static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blinko", isDirectory: true)
    }

    /// `BLINKO_AGENT_SOCKET` overrides the path (tests, multiple builds).
    public static var socketPath: String {
        if let custom = ProcessInfo.processInfo.environment["BLINKO_AGENT_SOCKET"], !custom.isEmpty { return custom }
        return supportDirectory.appendingPathComponent("agents.sock").path
    }

    /// Stable copy of the CLI that Claude Code hooks call (survives moving or updating the app).
    public static var hookHelperPath: String {
        supportDirectory.appendingPathComponent("bin/blinko").path
    }
}

/// One protocol line. Every field except `type` is optional; unknown fields are ignored.
public struct AgentMessage: Codable, Sendable, Equatable {
    public enum Kind {
        public static let hello = "hello"
        public static let sessionStart = "session_start"
        public static let sessionEnd = "session_end"
        public static let status = "status"
        public static let tool = "tool"
        public static let notification = "notification"
        public static let usage = "usage"
        public static let permissionRequest = "permission_request"
        public static let permissionResponse = "permission_response"
        public static let ack = "ack"
        public static let error = "error"
    }

    public var v: Int?
    public var type: String
    /// Session identifier, unique per agent.
    public var session: String?
    /// "claude-code", "codex", "cursor", … (free-form, lowercase).
    public var agent: String?
    /// Working directory of the session; its last path component is shown as the project name.
    public var cwd: String?
    /// Optional display name (overrides the folder name).
    public var title: String?
    /// "working" | "idle" | "waiting"
    public var state: String?
    public var detail: String?
    public var tool: String?
    /// "start" | "end" for `tool`
    public var phase: String?
    public var summary: String?
    public var message: String?
    /// Permission request id (echoed in the response).
    public var id: String?
    /// "allow" | "deny" | "ask" (ask = let the agent show its own prompt)
    public var decision: String?
    public var reason: String?
    public var tokens: Int?
    public var cost: Double?

    enum CodingKeys: String, CodingKey {
        case v, type, session, agent, cwd, title, state, detail, tool, phase, summary, message, id, decision, reason, tokens
        case cost = "cost_usd"
    }

    public init(type: String, session: String? = nil, agent: String? = nil, cwd: String? = nil, title: String? = nil,
                state: String? = nil, detail: String? = nil, tool: String? = nil, phase: String? = nil,
                summary: String? = nil, message: String? = nil, id: String? = nil, decision: String? = nil,
                reason: String? = nil, tokens: Int? = nil, cost: Double? = nil) {
        self.v = AgentProtocol.version
        self.type = type
        self.session = session
        self.agent = agent
        self.cwd = cwd
        self.title = title
        self.state = state
        self.detail = detail
        self.tool = tool
        self.phase = phase
        self.summary = summary
        self.message = message
        self.id = id
        self.decision = decision
        self.reason = reason
        self.tokens = tokens
        self.cost = cost
    }

    /// JSON + "\n"
    public func line() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = (try? encoder.encode(self)) ?? Data("{\"type\":\"error\"}".utf8)
        data.append(0x0A)
        return data
    }

    public static func decode(_ line: Data) -> AgentMessage? {
        try? JSONDecoder().decode(AgentMessage.self, from: line)
    }
}

public extension String {
    /// First line, whitespace-collapsed, at most `limit` characters (with an ellipsis).
    func agentClipped(_ limit: Int) -> String {
        let firstLine = split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }
}
