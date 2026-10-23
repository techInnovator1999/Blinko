import SwiftUI

/// Agents tab: the oldest pending approval as a card (Approve / Deny), otherwise the list
/// of sessions. Observes `AgentHubService` only here, at the leaf.
struct AgentsView: View {
    let vm: NotchViewModel

    var body: some View {
        let hub = AgentHubService.shared
        ZStack(alignment: .top) {
            if let approval = hub.approvals.first {
                ApprovalCard(vm: vm, approval: approval, index: 1, count: hub.approvals.count)
                    .id(approval.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97)), removal: .opacity))
            } else if hub.sessions.isEmpty {
                AgentsEmptyState(vm: vm)
                    .transition(.opacity)
            } else {
                SessionList(sessions: hub.sessions)
                    .transition(.opacity)
            }
        }
        .animation(Motion.content, value: hub.approvals.first?.id)
        .animation(Motion.content, value: hub.sessions.isEmpty)
    }
}

// MARK: - Approval

private struct ApprovalCard: View {
    let vm: NotchViewModel
    let approval: AgentApproval
    let index: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                AgentGlyph(agent: approval.agent, state: .waiting, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(verbatim: approval.project)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                            .lineLimit(1)
                        Text(verbatim: AgentKind.name(approval.agent))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.tertiaryText)
                            .lineLimit(1)
                    }
                    Text("wants to use \(Text(verbatim: approval.tool).foregroundStyle(Color.agentAccent))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if count > 1 {
                    Text("\(index) of \(count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.secondaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Capsule().fill(Color.fillSubtle))
                }
                Countdown(deadline: approval.deadline)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: approval.summary ?? approval.tool)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let detail = approval.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.hairline, lineWidth: 1))

            HStack(spacing: 8) {
                Button { decide("ask") } label: {
                    Text("Answer in Terminal")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.tertiaryText)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .help("Let the agent show its own prompt")
                Spacer()
                DecisionButton(title: "Deny", hint: "esc", style: .deny) { decide("deny") }
                    .keyboardShortcut(.cancelAction)
                DecisionButton(title: "Approve", hint: "⌘↩", style: .approve) { decide("allow") }
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.agentAccent.opacity(0.16), Color.agentAccent.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.agentAccent.opacity(0.28), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Clicking the card focuses it, so ⌘↩ / esc answer without the mouse.
        .onTapGesture { vm.requestKey?() }
    }

    private func decide(_ decision: String) {
        let hub = AgentHubService.shared
        withAnimation(Motion.content) { hub.decide(approval, decision) }
        if hub.approvals.isEmpty { vm.relinquishKey?() }
    }
}

private struct DecisionButton: View {
    enum Style { case approve, deny }
    let title: LocalizedStringKey
    let hint: String
    let style: Style
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Text(verbatim: hint)
                    .font(.system(size: 9.5, weight: .semibold))
                    .opacity(0.55)
            }
            .foregroundStyle(style == .approve ? Color.black : Color.primaryText)
            .padding(.horizontal, 13)
            .frame(height: 27)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
    }

    private var fill: Color {
        switch style {
        case .approve: Color.white.opacity(hovering ? 1 : 0.92)
        case .deny: Color.red.opacity(hovering ? 0.42 : 0.26)
        }
    }
}

/// Time left before the agent falls back to its own prompt (ticks only while visible).
private struct Countdown: View {
    let deadline: Date

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "timer").font(.system(size: 9, weight: .bold))
            Text(timerInterval: Date.now...max(deadline, .now), countsDown: true)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .frame(minWidth: 28, alignment: .leading)
        }
        .foregroundStyle(Color.tertiaryText)
        .help("Then the agent asks in its own window")
    }
}

// MARK: - Sessions

private struct SessionList: View {
    let sessions: [AgentSession]

    var body: some View {
        let rows = VStack(spacing: 4) {
            ForEach(sessions) { session in
                SessionRow(session: session)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.content, value: sessions.map(\.id))
        if sessions.count <= 3 {
            rows
        } else {
            ScrollView(.vertical, showsIndicators: false) { rows }
        }
    }
}

private struct SessionRow: View {
    let session: AgentSession
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            AgentGlyph(agent: session.agent, state: session.state, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(verbatim: session.project)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primaryText)
                        .lineLimit(1)
                    Text(verbatim: AgentKind.name(session.agent))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.tertiaryText)
                        .lineLimit(1)
                }
                Text(verbatim: session.detail ?? "")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let cost = session.cost {
                Text(cost, format: .currency(code: "USD").precision(.fractionLength(2)))
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.tertiaryText)
            }
            StatePill(state: session.state, since: session.stateSince)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hovering ? Color.fillHover : Color.fillSubtle))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .onTapGesture(count: 2) {
            if let cwd = session.cwd { NSWorkspace.shared.open(URL(fileURLWithPath: cwd)) }
        }
        .help(session.cwd ?? "")
    }
}

private struct StatePill: View {
    let state: AgentState
    let since: Date

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(state.tint).frame(width: 6, height: 6)
            Text(state.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(state == .idle ? Color.secondaryText : state.tint)
            // Elapsed in the current state, refreshed twice a minute while visible.
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(verbatim: Self.elapsed(from: since, to: ctx.date))
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.tertiaryText)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.05)))
        .fixedSize()
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        if s < 60 { return String(localized: "now") }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }
}

extension AgentState {
    var title: LocalizedStringKey {
        switch self {
        case .working: "Working"
        case .idle: "Idle"
        case .waiting: "Needs approval"
        }
    }

    var tint: Color {
        switch self {
        case .working: .agentAccent
        case .idle: Color.white.opacity(0.35)
        case .waiting: .orange
        }
    }
}

/// Agent mark in a tinted circle; a spinner ring runs around it while working.
private struct AgentGlyph: View {
    let agent: String
    let state: AgentState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(state == .idle ? Color.white.opacity(0.08) : state.tint.opacity(0.2))
            Image(systemName: state == .waiting ? "hand.raised.fill" : AgentKind.symbol(agent))
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(state == .idle ? Color.secondaryText : state.tint)
            if state == .working {
                AgentSpinner(tint: .agentAccent, lineWidth: 1.5).padding(-2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Empty

private struct AgentsEmptyState: View {
    let vm: NotchViewModel

    var body: some View {
        let hub = AgentHubService.shared
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.agentAccent.opacity(0.16))
                Image(systemName: "asterisk")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.agentAccent)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                if !Preferences.shared.agentHubEnabled {
                    Text("Agent Hub is off").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primaryText)
                    Text("Turn it on to see coding agents and approve their requests here.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondaryText)
                } else if hub.claudeHooksInstalled {
                    Text("No active sessions").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primaryText)
                    Text("Start Claude Code in a terminal: its status and permission requests show up here.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondaryText)
                } else {
                    Text("Connect your coding agents").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primaryText)
                    Text("See what Claude Code is doing and approve its requests from the notch.")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.secondaryText)
                }
                if !hub.claudeHooksInstalled || !Preferences.shared.agentHubEnabled {
                    PillButton(title: "Set Up…", symbol: "gearshape.fill") {
                        vm.close()
                        SettingsWindowController.shared.show(pane: .agents)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hub.checkHooks() }
    }
}
