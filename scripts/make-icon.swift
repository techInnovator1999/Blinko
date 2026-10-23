// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1),
                        NSColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)])!.draw(in: tilePath, angle: -90)
    // Accent glow
    NSGraphicsContext.current?.saveGraphicsState()
    tilePath.addClip()
    let glow = NSGradient(colors: [NSColor(red: 1, green: 0.35, blue: 0.55, alpha: 0.55), .clear])!
    glow.draw(fromCenter: NSPoint(x: tile.midX, y: tile.midY + tile.height * 0.05), radius: 0,
              toCenter: NSPoint(x: tile.midX, y: tile.midY), radius: tile.width * 0.55, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()
    // Island pill
    let pw = tile.width * 0.62, ph = tile.width * 0.2
    let pill = NSRect(x: tile.midX - pw / 2, y: tile.midY - ph / 2 + tile.height * 0.04, width: pw, height: ph)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: pill, xRadius: ph / 2, yRadius: ph / 2).fill()
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let stroke = NSBezierPath(roundedRect: pill, xRadius: ph / 2, yRadius: ph / 2); stroke.lineWidth = s * 0.004; stroke.stroke()
    // Dot + bars inside the pill
    let d = ph * 0.46
    NSColor(red: 1, green: 0.4, blue: 0.6, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: pill.minX + ph * 0.32, y: pill.midY - d / 2, width: d, height: d)).fill()
    let heights: [CGFloat] = [0.35, 0.7, 0.5, 0.85]
    let bw = ph * 0.085
    for (i, h) in heights.enumerated() {
        let bh = ph * h * 0.6
        let x = pill.maxX - ph * 0.42 - CGFloat(heights.count - 1 - i) * bw * 2
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: pill.midY - bh / 2, width: bw, height: bh), xRadius: bw / 2, yRadius: bw / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: set)
try! fm.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
