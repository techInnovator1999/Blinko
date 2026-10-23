import SwiftUI

/// One synced lyric line; a new line slides up and fades in while the old one fades out.
/// Lines too long for their slot glide sideways in time with the song (karaoke scroll):
/// a short hold, then a linear scroll that lands on the last word just before the next
/// line. Short lines stay still. Animates only while playing, so it costs nothing at rest.
struct LyricText: View {
    let index: Int?
    let size: CGFloat
    var alignment: Alignment = .leading

    var body: some View {
        let lines = LyricsService.shared.lines
        let valid = index.flatMap { lines.indices.contains($0) ? $0 : nil }
        let text = valid.map { lines[$0].text } ?? ""
        let start = valid.map { lines[$0].time } ?? 0
        let end = valid.flatMap { lines.indices.contains($0 + 1) ? lines[$0 + 1].time : nil } ?? start + 5
        ZStack(alignment: alignment) {
            MarqueeLine(text: text.isEmpty ? "♪" : text, size: size, alignment: alignment, lineEnd: end)
                .id(index ?? -1)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 5)),
                                        removal: .opacity.combined(with: .offset(y: -5))))
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .frame(height: size + 4)
        .clipped()
        .animation(Motion.content, value: index)
    }
}

private struct MarqueeLine: View {
    let text: String
    let size: CGFloat
    let alignment: Alignment
    let lineEnd: TimeInterval

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = max(0, textWidth - geo.size.width)
            Text(verbatim: text)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize()
                .background(GeometryReader { t in
                    Color.clear.onAppear { textWidth = t.size.width }
                })
                .offset(x: overflow > 0 ? offset : 0)
                .frame(width: geo.size.width, height: geo.size.height, alignment: overflow > 0 ? .leading : alignment)
                .mask {
                    // Soft edges only while scrolling, so clipped words fade instead of chopping.
                    LinearGradient(stops: overflow > 0
                                   ? [.init(color: offset < -1 ? .clear : .black, location: 0),
                                      .init(color: .black, location: 0.07),
                                      .init(color: .black, location: 0.93),
                                      .init(color: .clear, location: 1)]
                                   : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .task(id: overflow) { scroll(overflow: overflow) }
        }
    }

    private func scroll(overflow: CGFloat) {
        let np = NowPlayingService.shared
        guard overflow > 0, np.isPlaying else { return }
        let remaining = max(1, lineEnd - np.elapsed())
        let hold = min(0.7, remaining * 0.18)
        let travel = max(0.8, remaining - hold - 0.35)
        withAnimation(.linear(duration: travel).delay(hold)) { offset = -overflow }
    }
}
