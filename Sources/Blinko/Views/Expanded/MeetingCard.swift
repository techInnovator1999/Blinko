import AppKit
import SwiftUI

/// Home's left column: the meeting card while a call is active, the player otherwise.
struct HomePrimaryView: View {
    var body: some View {
        if Preferences.shared.meetingMode, MeetingService.shared.isInCall {
            MeetingCard()
                .transition(.opacity.combined(with: .offset(y: 6)))
        } else {
            MediaPlayerView()
        }
    }
}

/// Icon of the app hosting the call (cached by NSWorkspace).
struct MeetingAppIcon: View {
    let call: ActiveCall
    var size: CGFloat

    var body: some View {
        Group {
            if let image = Self.icon(for: call) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.green.gradient)
                    .overlay(Image(systemName: call.app.symbol)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size)
    }

    static func icon(for call: ActiveCall) -> NSImage? {
        let url = NSRunningApplication(processIdentifier: call.pid)?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: call.bundleID)
        return url.map { FileIcons.icon(for: $0) }
    }
}

/// File and app icons as small cached bitmaps. NSWorkspace icons carry every size
/// representation; one 64 px bitmap is cheaper to draw (and snapshots render it correctly).
@MainActor
enum FileIcons {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    static func icon(for url: URL) -> NSImage {
        if let cached = cache.object(forKey: url.path as NSString) { return cached }
        let source = NSWorkspace.shared.icon(forFile: url.path)
        // Redrawn into plain 8-bit sRGB: icons can come as 16-bit / wide-gamut bitmaps.
        var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        var image = source
        if let cg = source.cgImage(forProposedRect: &rect, context: nil, hints: nil),
           let space = CGColorSpace(name: CGColorSpace.sRGB),
           let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            if let out = ctx.makeImage() { image = NSImage(cgImage: out, size: NSSize(width: 32, height: 32)) }
        }
        cache.setObject(image, forKey: url.path as NSString)
        return image
    }
}

// MARK: - Expanded card

struct MeetingCard: View {
    var body: some View {
        let meeting = MeetingService.shared
        if let call = meeting.call {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    MeetingAppIcon(call: call, size: 46)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                        .onTapGesture { meeting.bringToFront() }
                    VStack(alignment: .leading, spacing: 3) {
                        MeetingTitle(call: call)
                        HStack(spacing: 6) {
                            LiveDot()
                            Text(verbatim: call.displayName)
                            Text(verbatim: "·").foregroundStyle(Color.tertiaryText)
                            Text(timerInterval: call.start...call.start.addingTimeInterval(86_400), countsDown: false)
                                .monospacedDigit()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondaryText)
                        .lineLimit(1)
                        if meeting.appMuted, !meeting.micMuted {
                            Text("Muted in \(call.displayName)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red)
                                .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 0)
                }
                MeetingControls(call: call)
            }
            .padding(.top, 10)
            .animation(Motion.micro, value: meeting.isMuted)
        }
    }
}

/// Calendar event happening now, else "<App> call".
private struct MeetingTitle: View {
    let call: ActiveCall

    var body: some View {
        let event = MeetingService.currentEvent(in: CalendarService.shared.items)
        Group {
            if let event {
                Text(verbatim: event.title)
            } else {
                Text("\(call.displayName) call")
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color.primaryText)
        .lineLimit(1)
    }
}

private struct LiveDot: View {
    var body: some View {
        Circle().fill(Color.green)
            .frame(width: 6, height: 6)
            .shadow(color: .green.opacity(0.8), radius: 3)
    }
}

private struct MeetingControls: View {
    let call: ActiveCall

    var body: some View {
        let meeting = MeetingService.shared
        let camera = PrivacyService.shared.cameraInUse
        HStack(spacing: 14) {
            RoundControl(symbol: meeting.micMuted ? "mic.slash.fill" : "mic.fill",
                         caption: meeting.micMuted ? "Unmute" : "Mute",
                         fill: meeting.micMuted ? Color.red : Color.white.opacity(0.14),
                         help: "Mutes the microphone for every app") {
                meeting.toggleMute()
            }
            RoundControl(symbol: camera ? "video.fill" : "video.slash.fill",
                         caption: camera ? "Camera On" : "Camera Off",
                         fill: camera ? Color.green.opacity(0.85) : Color.white.opacity(0.08),
                         help: "Camera status", enabled: false) {}
            RoundControl(symbol: "macwindow", caption: "Show",
                         fill: Color.white.opacity(0.14), help: "Bring the call to the front") {
                meeting.bringToFront()
            }
            if call.app.leave != nil {
                RoundControl(symbol: "phone.down.fill", caption: "Leave", fill: Color.red,
                             help: meeting.canLeave ? "Leave the call" : "Brings the call to the front (needs Accessibility to leave from here)") {
                    meeting.leave()
                }
            }
        }
    }
}

/// FaceTime-style round button with a caption underneath.
private struct RoundControl: View {
    let symbol: String
    let caption: LocalizedStringKey
    let fill: Color
    var help: LocalizedStringKey = ""
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(fill))
                    .overlay(Circle().fill(Color.white.opacity(hovering && enabled ? 0.12 : 0)))
                Text(caption)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .allowsHitTesting(enabled)
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help(help)
    }
}

// MARK: - Compact (closed island)

struct MeetingCompactLeading: View {
    var body: some View {
        if let call = MeetingService.shared.call {
            MeetingAppIcon(call: call, size: 18)
        }
    }
}

struct MeetingCompactTrailing: View {
    var body: some View {
        let meeting = MeetingService.shared
        if let call = meeting.call {
            HStack(spacing: 5) {
                if PrivacyService.shared.cameraInUse {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                }
                Image(systemName: meeting.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(meeting.isMuted ? Color.red : .green)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 13)
                Text(timerInterval: call.start...call.start.addingTimeInterval(86_400), countsDown: false)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 50, alignment: .trailing)
            }
            .fixedSize()
        }
    }
}

/// "You're muted" warning: leading wing.
struct MutedWarningLeading: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            Text("You're muted")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize()
        }
    }
}

/// "You're muted" warning: trailing wing with a quick Unmute.
struct MutedWarningTrailing: View {
    @State private var hovering = false

    var body: some View {
        Button {
            MeetingService.shared.unmuteEverywhere()
            ActivityCenter.shared.dismiss()
        } label: {
            Text("Unmute")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 21)
                .background(Capsule().fill(Color.red.opacity(hovering ? 1 : 0.88)))
                .fixedSize()
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .onHover { hovering = $0 }
    }
}
