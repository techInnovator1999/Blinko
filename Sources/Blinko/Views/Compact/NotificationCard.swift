import SwiftUI

/// The island dropped down into a message card for a mirrored notification (Slack…):
/// app in the notch row, avatar + sender + #channel chip, the message, and a countdown
/// line. Hover pauses it and offers Reply; click opens the conversation.
struct NotificationCard: View {
    let note: MirroredNotification
    let notch: CGSize
    let notchWidth: CGFloat

    @State private var hovering = false
    @State private var remaining: CGFloat = 1

    var body: some View {
        let parts = MessageParts(note)
        VStack(spacing: 0) {
            // Notch row: app on the left wing, time on the right.
            HStack(spacing: 6) {
                AppBadge(app: note.app, size: 15)
                Text(verbatim: note.app)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: notchWidth + 12)
                Text("now")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.tertiaryText)
            }
            .padding(.horizontal, 22)
            .frame(height: notch.height)

            HStack(alignment: .center, spacing: 12) {
                Avatar(name: parts.sender, app: note.app)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verbatim: parts.sender)
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let place = parts.place {
                            Text(verbatim: place)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                    }
                    Text(verbatim: parts.message)
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if hovering {
                    Button { NotificationMirrorService.shared.open(note) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 9, weight: .bold))
                            Text("Reply").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white))
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)

            Spacer(minLength: 0)

            // Countdown until the card tucks back into the notch (pauses while hovered).
            GeometryReader { geo in
                Capsule()
                    .fill(Theme.shared.accent.opacity(0.85))
                    .frame(width: geo.size.width * remaining, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
            .padding(.horizontal, 30)
            .padding(.bottom, 9)
            .opacity(hovering ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { NotificationMirrorService.shared.open(note) }
        .onHover { inside in
            withAnimation(Motion.micro) { hovering = inside }
            if inside {
                remaining = 1
            } else {
                withAnimation(.linear(duration: 2.5)) { remaining = 0 }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: ActivityCenter.shared.currentDuration)) { remaining = 0 }
        }
        .help("Open in \(note.app)")
    }
}

/// Splits a banner into who / where / what. Slack channel messages arrive as
/// title "#channel", body "Name: message"; DMs as title "Name", body "message".
struct MessageParts {
    let sender: String
    let place: String?
    let message: String

    init(_ note: MirroredNotification) {
        let body = note.body ?? ""
        let titleIsPlace = note.title.hasPrefix("#") || note.title.contains(" in #")
        var sender = note.title
        var place: String? = note.subtitle
        var message = body
        if titleIsPlace {
            place = note.title
            if let colon = body.firstIndex(of: ":"), body.distance(from: body.startIndex, to: colon) <= 40 {
                sender = String(body[..<colon]).trimmingCharacters(in: .whitespaces)
                message = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else {
                sender = note.app
            }
        }
        if let p = place, p.isEmpty || p == sender { place = nil }
        self.sender = sender.isEmpty ? note.app : sender
        self.place = place
        self.message = message.isEmpty ? String(localized: "New notification") : message
    }
}

/// Initials on a colour picked from the name (stable per person), with the app badge.
private struct Avatar: View {
    let name: String
    let app: String

    private static let palette: [Color] = [
        Color(red: 0.88, green: 0.30, blue: 0.47), Color(red: 0.36, green: 0.42, blue: 0.95),
        Color(red: 0.17, green: 0.67, blue: 0.56), Color(red: 0.95, green: 0.58, blue: 0.20),
        Color(red: 0.60, green: 0.38, blue: 0.90), Color(red: 0.20, green: 0.62, blue: 0.86),
    ]

    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        let color = Self.palette[abs(name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.palette.count]
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 42, height: 42)
                .overlay(Text(verbatim: initials.isEmpty ? "•" : initials)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white))
            AppBadge(app: app, size: 18)
                .padding(2)
                .background(Circle().fill(Color.black))
                .offset(x: 4, y: 4)
        }
    }
}

private struct AppBadge: View {
    let app: String
    let size: CGFloat

    var body: some View {
        if let icon = NotificationMirrorService.icon(for: app) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: size * 0.7, weight: .semibold))
                .foregroundStyle(Theme.shared.accent)
                .frame(width: size, height: size)
        }
    }
}

/// Slim message toast shown over the open island (e.g. Slack while Claude's approval card is up).
struct OpenIslandToast: View {
    let notchHeight: CGFloat
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .top) {
            if case .appNotification(let note) = ActivityCenter.shared.current {
                let parts = MessageParts(note)
                HStack(spacing: 10) {
                    ToastIcon(app: note.app)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(verbatim: parts.sender).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            if let place = parts.place {
                                Text(verbatim: place).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.6))
                            }
                        }
                        .lineLimit(1)
                        Text(verbatim: parts.message)
                            .font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(hovering ? "Reply" : "now")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(hovering ? Color.black : Color.tertiaryText)
                        .padding(.horizontal, hovering ? 9 : 0)
                        .frame(height: 22)
                        .background(Capsule().fill(hovering ? Color.white : .clear))
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(white: 0.11))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
                        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                )
                .padding(.horizontal, 40)
                .padding(.top, notchHeight + 6)
                .contentShape(Rectangle())
                .onTapGesture { NotificationMirrorService.shared.open(note) }
                .onHover { inside in
                    withAnimation(Motion.micro) { hovering = inside }
                    ActivityCenter.shared.hold(inside)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(note.id)
            }
        }
        .animation(Motion.open, value: ActivityCenter.shared.current)
    }
}

private struct ToastIcon: View {
    let app: String
    var body: some View {
        if let icon = NotificationMirrorService.icon(for: app) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 26, height: 26)
        } else {
            Image(systemName: "bell.badge.fill").font(.system(size: 16)).foregroundStyle(Theme.shared.accent).frame(width: 26, height: 26)
        }
    }
}
