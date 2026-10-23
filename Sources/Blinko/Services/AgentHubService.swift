import AppKit
import BlinkoKit
import Observation
import os

private let log = Logger(subsystem: "app.blinko.Blinko", category: "agents")

enum AgentState: String {
    case working, idle, waiting
}

/// One coding-agent session (a Claude Code window, a Codex run…).
struct AgentSession: Identifiable, Equatable {
    let id: String
    var agent: String
    var cwd: String?
    var title: String?
    var state: AgentState
    /// Last thing that happened, in a few words ("npm test", "Finished", the prompt…).
    var detail: String?
    /// Tool currently running.
    var tool: String?
    var startedAt: Date
    var updatedAt: Date
    var stateSince: Date
    var tokens: Int?
    var cost: Double?

    var project: String {
        if let title, !title.isEmpty { return title }
        if let cwd, !cwd.isEmpty { return (cwd as NSString).lastPathComponent }
        return AgentKind.name(agent)
    }
}

/// A permission request waiting for Approve / Deny. Answered on the connection it came from.
struct AgentApproval: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let connection: AgentHubServer.ConnectionID
    var agent: String
    var project: String
    var tool: String
    var summary: String?
    var detail: String?
    let receivedAt: Date
    let deadline: Date
}

/// Display names and glyphs for known agents; anything else gets a generic look.
enum AgentKind {
    static func name(_ agent: String) -> String {
        switch agent.lowercased() {
        case "claude-code", "claude": "Claude Code"
        case "codex": "Codex"
        case "cursor": "Cursor"
        case "gemini", "gemini-cli": "Gemini CLI"
        case "aider": "Aider"
        default: agent.isEmpty ? String(localized: "Agent") : agent.capitalized
        }
    }

    static func symbol(_ agent: String) -> String {
        switch agent.lowercased() {
        case "claude-code", "claude": "asterisk"
        case "codex": "chevron.left.forwardslash.chevron.right"
        case "cursor": "cursorarrow.rays"
        default: "cpu"
        }
    }
}

/// Live status of AI coding agents + permission approvals, fed by the local socket.
/// Off = no socket, no work. On = one listening socket; nothing runs between messages
/// except one staleness work item while a session claims to be working.
@MainActor
@Observable
final class AgentHubService {
    static let shared = AgentHubService()

    /// Most recently active first.
    private(set) var sessions: [AgentSession] = []
    /// Oldest first; the island shows the first.
    private(set) var approvals: [AgentApproval] = []
    private(set) var isListening = false
    private(set) var lastError: String?
    /// Whether Blinko's hooks are in ~/.claude/settings.json (refreshed by `checkHooks()`).
    private(set) var claudeHooksInstalled = false

    @ObservationIgnored private var server: AgentHubServer?
    @ObservationIgnored private var expiry: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var staleWork: DispatchWorkItem?
    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private var didStartOnce = false

    var hasActivity: Bool { !approvals.isEmpty || sessions.contains { $0.state == .working } }
    var workingCount: Int { sessions.filter { $0.state != .idle }.count }

    /// The session the closed island shows: the one asking for approval, else the latest working one.
    var featured: AgentSession? {
        if let first = approvals.first, let s = sessions.first(where: { $0.id == first.sessionID }) { return s }
        return sessions.first { $0.state == .working }
    }

    // MARK: Lifecycle

    func refresh() {
        if !didStartOnce {
            didStartOnce = true
            introduceTab()
            checkHooks(updateHelper: true)
        }
        prefs.agentHubEnabled ? start() : stop()
    }

    private func start() {
        guard server == nil else { return }
        let server = AgentHubServer(path: AgentProtocol.socketPath)
        server.onMessage = { [weak self] id, message in self?.handle(message, from: id) }
        server.onDisconnect = { [weak self] id in self?.connectionClosed(id) }
        do {
            try server.start()
            self.server = server
            isListening = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("agent hub failed to listen: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stop() {
        guard let server else { return }
        for approval in approvals { server.send(response(approval.id, "ask"), to: approval.connection) }
        server.stop()
        self.server = nil
        isListening = false
        approvals.removeAll()
        expiry.values.forEach { $0.cancel() }
        expiry.removeAll()
        staleWork?.cancel()
        sessions.removeAll()
    }

    /// The Agents tab is new in v0.4: keep it out of the header until an agent is connected.
    private func introduceTab() {
        let store = UserDefaults.standard
        guard !store.bool(forKey: "agentsTabIntroduced") else { return }
        store.set(true, forKey: "agentsTabIntroduced")
        if !ClaudeHooks.isInstalled() { prefs.hiddenTabs.insert(.agents) }
    }

    private func revealTab() {
        if prefs.hiddenTabs.contains(.agents) { prefs.hiddenTabs.remove(.agents) }
    }

    // MARK: Claude Code hooks

    /// The CLI inside the app bundle (Contents/Helpers/blinko).
    static var bundledCLI: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/blinko")
    }

    /// Re-reads settings.json; when hooks are installed, keeps the stable helper copy current.
    func checkHooks(updateHelper: Bool = false) {
        let source = Self.bundledCLI
        DispatchQueue.global(qos: .utility).async {
            let installed = ClaudeHooks.isInstalled()
            if installed, updateHelper, FileManager.default.isExecutableFile(atPath: source.path) {
                _ = try? HookHelper.install(from: source)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { AgentHubService.shared.claudeHooksInstalled = installed } }
        }
    }

    func installClaudeHooks() throws {
        guard FileManager.default.isExecutableFile(atPath: Self.bundledCLI.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "The blinko helper is missing from the app bundle. Build Blinko with scripts/build.sh.")])
        }
        try HookHelper.install(from: Self.bundledCLI)
        try ClaudeHooks.install(helperPath: AgentProtocol.hookHelperPath)
        claudeHooksInstalled = true
        prefs.agentHubEnabled = true
        revealTab()
    }

    func uninstallClaudeHooks() throws {
        try ClaudeHooks.uninstall()
        claudeHooksInstalled = false
    }

    // MARK: Messages

    private func handle(_ m: AgentMessage, from connection: AgentHubServer.ConnectionID) {
        let now = Date()
        switch m.type {
        case AgentMessage.Kind.hello:
            server?.send(AgentMessage(type: AgentMessage.Kind.ack), to: connection)
            return
        case AgentMessage.Kind.permissionResponse:
            #if DEBUG
            // Debug builds only: lets the end-to-end test answer without clicking ("*" = oldest request).
            if let id = m.id, let approval = id == "*" ? approvals.first : approvals.first(where: { $0.id == id }) {
                decide(approval, m.decision ?? "ask")
            }
            #endif
            return
        default: break
        }
        guard let sessionKey = m.session, !sessionKey.isEmpty else { return }
        let agent = (m.agent ?? "agent").lowercased()
        let id = "\(agent):\(sessionKey)"

        if m.type == AgentMessage.Kind.sessionEnd {
            sessions.removeAll { $0.id == id }
            workingSince[id] = nil
            resolveApprovals(ofSession: id, with: "ask")
            scheduleStaleCheck()
            return
        }

        var session = sessions.first { $0.id == id }
            ?? AgentSession(id: id, agent: agent, cwd: nil, title: nil, state: .idle, detail: nil, tool: nil,
                            startedAt: now, updatedAt: now, stateSince: now)
        if let cwd = m.cwd, !cwd.isEmpty { session.cwd = cwd }
        if let title = m.title, !title.isEmpty { session.title = title.agentClipped(60) }
        if let tokens = m.tokens { session.tokens = tokens }
        if let cost = m.cost { session.cost = cost }
        session.updatedAt = now
        let previous = session.state

        switch m.type {
        case AgentMessage.Kind.sessionStart:
            setState(&session, .idle, at: now)
            session.detail = String(localized: "Session started")
        case AgentMessage.Kind.status:
            let state = AgentState(rawValue: m.state ?? "") ?? .working
            let workedSince = previous == .working ? workingSince[id] : nil
            setState(&session, state, at: now)
            if state != .working { session.tool = nil }
            if let detail = m.detail ?? m.message { session.detail = detail.agentClipped(120) }
            // "Finished" only after a real stretch of work, not for quick answers.
            if state == .idle, session.state == .idle, prefs.agentFinishedAlert,
               let since = workedSince, now.timeIntervalSince(since) >= 15 {
                ActivityCenter.shared.show(.custom(CustomAlert(
                    title: session.project, body: String(localized: "Finished"), symbol: "checkmark.circle.fill",
                    color: "green", duration: 3)))
                SoundService.shared.play(.agentFinished)
            }
        case AgentMessage.Kind.tool:
            setState(&session, .working, at: now)
            let text = [m.tool, m.summary].compactMap { $0 }.joined(separator: " · ")
            if !text.isEmpty { session.detail = text.agentClipped(120) }
            session.tool = m.phase == "end" ? nil : m.tool
        case AgentMessage.Kind.notification:
            if let text = m.message ?? m.detail, !text.isEmpty {
                session.detail = text.agentClipped(120)
                if prefs.agentNotifications {
                    ActivityCenter.shared.show(.custom(CustomAlert(
                        title: session.project, body: text.agentClipped(60), symbol: "bell.fill", color: "orange", duration: 4)))
                    SoundService.shared.play(.agentNotification)
                }
            }
        case AgentMessage.Kind.usage:
            break
        case AgentMessage.Kind.permissionRequest:
            guard let requestID = m.id, !requestID.isEmpty else { return }
            guard prefs.agentApprovals else {
                server?.send(response(requestID, "ask"), to: connection)
                break
            }
            let approval = AgentApproval(
                id: requestID, sessionID: id, connection: connection, agent: agent, project: session.project,
                tool: m.tool ?? String(localized: "Tool"), summary: m.summary?.agentClipped(200),
                detail: m.detail?.agentClipped(140), receivedAt: now,
                deadline: now.addingTimeInterval(prefs.agentApprovalTimeout))
            approvals.removeAll { $0.id == requestID }
            approvals.append(approval)
            armExpiry(approval)
            SoundService.shared.play(.agentApproval)
            setState(&session, .waiting, at: now)
            session.detail = [m.tool, m.summary].compactMap { $0 }.joined(separator: " · ").agentClipped(120)
            upsert(session)
            revealTab()
            if prefs.agentAutoOpen { AppRouter.shared.presentApproval() }
            scheduleStaleCheck()
            return
        default:
            return
        }
        upsert(session)
        scheduleStaleCheck()
    }

    /// When each session's current working stretch began (approvals don't restart it).
    @ObservationIgnored private var workingSince: [String: Date] = [:]

    private func setState(_ session: inout AgentSession, _ state: AgentState, at date: Date) {
        // A session with an open approval stays "waiting" until it is answered.
        let pending = approvals.contains { $0.sessionID == session.id }
        let target: AgentState = pending ? .waiting : state
        guard session.state != target else { return }
        if target == .working, session.state == .idle { workingSince[session.id] = date }
        session.state = target
        session.stateSince = date
    }

    private func upsert(_ session: AgentSession) {
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            if i == 0 { sessions[0] = session } else { sessions.remove(at: i); sessions.insert(session, at: 0) }
        } else {
            sessions.insert(session, at: 0)
            if sessions.count > 12 { sessions.removeLast(sessions.count - 12) }
        }
    }

    // MARK: Approvals

    /// "allow" / "deny" / "ask" (= let the agent show its own prompt).
    func decide(_ approval: AgentApproval, _ decision: String) {
        guard approvals.contains(where: { $0.id == approval.id }) else { return }
        let reason = decision == "deny" ? String(localized: "Denied in Blinko") : nil
        server?.send(response(approval.id, decision, reason: reason), to: approval.connection)
        finish(approval.id)
        if let i = sessions.firstIndex(where: { $0.id == approval.sessionID }),
           !approvals.contains(where: { $0.sessionID == approval.sessionID }) {
            sessions[i].state = decision == "deny" ? .idle : .working
            sessions[i].stateSince = .now
            sessions[i].detail = (decision == "allow" ? String(localized: "Approved") :
                                  decision == "deny" ? String(localized: "Denied") : String(localized: "Answer in the terminal"))
                + " · " + approval.tool
        }
        if approvals.isEmpty { AppRouter.shared.approvalsCleared() }
    }

    private func response(_ id: String, _ decision: String, reason: String? = nil) -> AgentMessage {
        AgentMessage(type: AgentMessage.Kind.permissionResponse, id: id, decision: decision, reason: reason)
    }

    private func finish(_ id: String) {
        expiry.removeValue(forKey: id)?.cancel()
        approvals.removeAll { $0.id == id }
    }

    private func armExpiry(_ approval: AgentApproval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, let a = self.approvals.first(where: { $0.id == approval.id }) else { return }
            self.decide(a, "ask")
        }
        expiry[approval.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(5, approval.deadline.timeIntervalSinceNow), execute: work)
    }

    private func resolveApprovals(ofSession id: String, with decision: String) {
        for approval in approvals where approval.sessionID == id { decide(approval, decision) }
    }

    /// The client went away (agent answered in its own UI, was interrupted, or quit).
    private func connectionClosed(_ connection: AgentHubServer.ConnectionID) {
        let gone = approvals.filter { $0.connection == connection }
        guard !gone.isEmpty else { return }
        for approval in gone {
            finish(approval.id)
            if let i = sessions.firstIndex(where: { $0.id == approval.sessionID }),
               !approvals.contains(where: { $0.sessionID == approval.sessionID }) {
                sessions[i].state = .working
                sessions[i].stateSince = .now
            }
        }
        if approvals.isEmpty { AppRouter.shared.approvalsCleared() }
    }

    // MARK: Staleness

    /// Agents that crash never say goodbye. While a session claims to be working, one work
    /// item checks again after the quiet period; idle sessions are dropped after a few hours.
    private func scheduleStaleCheck() {
        staleWork?.cancel()
        staleWork = nil
        let quiet: TimeInterval = 10 * 60
        let now = Date()
        sessions.removeAll { $0.state == .idle && now.timeIntervalSince($0.updatedAt) > 3 * 3600 }
        let working = sessions.filter { $0.state == .working }
        guard let oldest = working.map(\.updatedAt).min() else { return }
        let delay = max(5, oldest.addingTimeInterval(quiet).timeIntervalSince(now))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = Date()
            for i in self.sessions.indices where self.sessions[i].state == .working
                && now.timeIntervalSince(self.sessions[i].updatedAt) >= quiet {
                self.sessions[i].state = .idle
                self.sessions[i].tool = nil
                self.sessions[i].stateSince = now
                self.sessions[i].detail = String(localized: "No recent activity")
            }
            self.scheduleStaleCheck()
        }
        staleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Preview

    /// Design-time state for snapshot rendering.
    func injectPreview(sessions: [AgentSession], approvals: [AgentApproval]) {
        self.sessions = sessions
        self.approvals = approvals
    }
}
