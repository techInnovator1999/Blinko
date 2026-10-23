import AppKit
import SwiftUI

// MARK: - Buttons

/// Icon button with a soft hover plate and a press "squish". Hover state is local
/// @State, so hovering one button never invalidates anything else.
struct IslandIconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var plate: CGFloat = 28
    var tint: Color = .primaryText
    var help: LocalizedStringKey = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: plate, height: plate)
                .background(Circle().fill(hovering ? Color.fillHover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
        .help(help)
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.88
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.micro, value: configuration.isPressed)
    }
}

/// Rounded "pill" button for text actions.
struct PillButton: View {
    let title: LocalizedStringKey
    var symbol: String?
    var prominent = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.black : .primaryText)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(prominent ? Color.white.opacity(hovering ? 1 : 0.92)
                                                 : (hovering ? Color.fillHover : Color.fillSubtle)))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .onHover { hovering = $0 }
        .animation(Motion.micro, value: hovering)
    }
}

// MARK: - Progress

struct LevelBar: View {
    let value: Double
    var tint: Color = .white
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule().fill(tint)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(Motion.micro, value: value)
    }
}

struct RingProgress: View {
    let value: Double
    var tint: Color = .orange
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 8
    var placeholderSymbol = "music.note"

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: placeholderSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tertiaryText)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(Motion.content, value: image)
    }
}

// MARK: - Visualizer (Core Animation, render-server driven)

/// Music bars animated entirely by the window server's render loop via CAAnimation.
/// The app process does zero per-frame work; when paused, the animations are removed.
struct AudioVisualizer: NSViewRepresentable {
    var isPlaying: Bool
    var color: NSColor
    var barCount = 4

    func makeNSView(context: Context) -> VisualizerNSView {
        VisualizerNSView(barCount: barCount)
    }

    func updateNSView(_ view: VisualizerNSView, context: Context) {
        view.update(playing: isPlaying, color: color)
    }
}

final class VisualizerNSView: NSView {
    private var bars: [CALayer] = []
    private var playing: Bool?

    init(barCount: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.cornerRadius = 1.25
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let n = CGFloat(bars.count)
        let gap: CGFloat = 2
        let w = max(1.5, (bounds.width - gap * (n - 1)) / n)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            bar.cornerRadius = w / 2
        }
        CATransaction.commit()
    }

    func update(playing: Bool, color: NSColor) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.4)
        bars.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()

        guard playing != self.playing else { return }
        self.playing = playing
        Self.applyClassic(to: bars, playing: playing)
    }

    /// Installs the looping "eq" animation (playing) or settles the bars (paused).
    /// Shared with `SpectrumNSView`, which falls back to it without live audio.
    static func applyClassic(to bars: [CALayer], playing: Bool) {
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            if playing {
                let anim = CAKeyframeAnimation(keyPath: "transform.scale.y")
                let seeds: [CGFloat] = [0.35, 1, 0.55, 0.85, 0.3, 0.95, 0.5]
                let offset = (i * 2) % seeds.count
                var values: [CGFloat] = Array(seeds[offset...])
                values.append(contentsOf: seeds[..<offset])
                values.append(values[0])
                anim.values = values
                let durations: [CFTimeInterval] = [1.1, 0.9, 1.25, 1.0, 1.15]
                anim.duration = durations[i % durations.count]
                anim.calculationMode = .cubic
                anim.repeatCount = .infinity
                anim.isRemovedOnCompletion = false
                bar.add(anim, forKey: "eq")
                bar.transform = CATransform3DIdentity
            } else {
                let settle = CABasicAnimation(keyPath: "transform.scale.y")
                settle.fromValue = bar.presentation()?.value(forKeyPath: "transform.scale.y") ?? 1
                settle.toValue = 0.25
                settle.duration = 0.3
                bar.transform = CATransform3DMakeScale(1, 0.25, 1)
                bar.add(settle, forKey: "settle")
            }
        }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    var tint: Color = .white
    var normalize = false
    var capacity = 40

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let maxValue = normalize ? max(values.max() ?? 1, 1) : 1
            let step = size.width / CGFloat(capacity - 1)
            let start = size.width - CGFloat(values.count - 1) * step // newest sample on the right edge
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: start + CGFloat(i) * step, y: size.height * (1 - CGFloat(min(v / maxValue, 1))) )
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: start, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [tint.opacity(0.35), tint.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Formatting

enum Format {
    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "5 min", "1 hr" — readable timer names.
    static func duration(_ seconds: TimeInterval) -> String {
        durationFormatter.string(from: seconds) ?? time(seconds)
    }

    /// "5m", "1h" — compact preset labels.
    static func shortDuration(_ seconds: TimeInterval) -> String {
        shortDurationFormatter.string(from: seconds) ?? time(seconds)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .short
        f.maximumUnitCount = 2
        return f
    }()

    private static let shortDurationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 1
        return f
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowsNonnumericFormatting = false
        f.countStyle = .memory
        return f
    }()

    static func bytes(_ value: Double) -> String { byteFormatter.string(fromByteCount: Int64(value)) }
    static func rate(_ value: Double) -> String { byteFormatter.string(fromByteCount: Int64(value)) + "/s" }
}
