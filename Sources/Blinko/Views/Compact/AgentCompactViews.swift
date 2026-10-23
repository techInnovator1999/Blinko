import AppKit
import SwiftUI

// MARK: - Agent Hub in the closed island

extension Color {
    /// Claude's warm orange: the Agent Hub accent.
    static let agentAccent = Color(red: 0.85, green: 0.47, blue: 0.34)
}

/// Leading wing: spinner (working) or a raised hand (approval needed) + project name.
struct AgentCompactLeading: View {
    var body: some View {
        let hub = AgentHubService.shared
        let waiting = !hub.approvals.isEmpty
        HStack(spacing: 6) {
            if waiting {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.agentAccent)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                    .frame(width: 14)
            } else {
                AgentSpinner(tint: .agentAccent).frame(width: 13, height: 13)
            }
            Text(verbatim: hub.featured?.project ?? AgentKind.name(hub.featured?.agent ?? ""))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Trailing wing: "Approve?" while a request waits, else the running tool (+N sessions).
struct AgentCompactTrailing: View {
    var body: some View {
        let hub = AgentHubService.shared
        HStack(spacing: 4) {
            if !hub.approvals.isEmpty {
                Text("Approve?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.agentAccent)
                    .fixedSize()
                if hub.approvals.count > 1 { CountBadge(count: hub.approvals.count - 1) }
            } else {
                Group {
                    if let tool = hub.featured?.tool { Text(verbatim: tool) } else { Text("Working") }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
                if hub.workingCount > 1 { CountBadge(count: hub.workingCount - 1) }
            }
        }
    }
}

/// Render-server spinner (the download ring's arc) on a faint track: no per-frame app work.
struct AgentSpinner: View {
    let tint: Color
    var lineWidth: CGFloat = 2
    /// ImageRenderer can't draw AppKit views: snapshots get a still arc.
    nonisolated(unsafe) static var renderStatic = false

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            if Self.renderStatic {
                Circle().trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                AgentSpinnerArc(color: NSColor(tint), lineWidth: lineWidth)
            }
        }
    }
}

private struct AgentSpinnerArc: NSViewRepresentable {
    let color: NSColor
    let lineWidth: CGFloat
    func makeNSView(context: Context) -> SpinnerArcView { SpinnerArcView(color: color, lineWidth: lineWidth) }
    func updateNSView(_ view: SpinnerArcView, context: Context) {}
}

// MARK: - Custom alerts (blinko://alert, `blinko alert`)

enum AlertStyle {
    static func color(_ name: String) -> Color {
        let n = name.trimmingCharacters(in: .whitespaces).lowercased()
        switch n {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        case "claude", "agent": return .agentAccent
        default:
            let hex = n.hasPrefix("#") ? String(n.dropFirst()) : n
            if hex.count == 6, let v = UInt32(hex, radix: 16) {
                return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                             blue: Double(v & 0xFF) / 255)
            }
            return .white
        }
    }

    /// The SF Symbol if it exists, else a bell.
    static func validSymbol(_ name: String?) -> String {
        guard let name, !name.isEmpty, NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else {
            return "bell.fill"
        }
        return name
    }
}

struct CustomAlertLeading: View {
    let alert: CustomAlert

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: alert.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AlertStyle.color(alert.color))
                .symbolEffect(.bounce, value: alert)
            Text(verbatim: alert.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

struct CustomAlertTrailing: View {
    let alert: CustomAlert

    var body: some View {
        if let body = alert.body {
            Text(verbatim: body)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            // Keeps the wing's frame: modifiers on an empty view collapse it, off-centring the island.
            Color.clear.frame(width: 1, height: 1)
        }
    }
}
