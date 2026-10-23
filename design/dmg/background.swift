// Renders the DMG window background at 1x and 2x.
// Usage: swift design/dmg/background.swift <out-dir> <version>
//
// Modern Finder opens disk images at its own size (≈920×436 on macOS 27) regardless of the
// stored bounds, so the art is laid out for a 920×400 content area and the canvas extends
// dark far beyond it — no white edges at any window size. Coordinates below are measured
// from the top-left, like Finder's icon positions.
import AppKit

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")
let version = args.count > 2 ? args[2] : ""
let canvas = CGSize(width: 1800, height: 1100)   // dark bleed for big windows
let content = CGSize(width: 920, height: 400)     // what Finder shows by default
let cx = content.width / 2
let logo = NSImage(contentsOfFile: "design/logo-1024.png")
// Finder icon centres (keep in sync with design/dmg/settings.py and scripts/make-dmg.sh).
let appX: CGFloat = 300, appsX: CGFloat = 620, iconY: CGFloat = 190

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }
    func y(_ fromTop: CGFloat) -> CGFloat { canvas.height - fromTop }   // top-left → AppKit

    ctx.setFillColor(c(10, 9, 18)); ctx.fill(CGRect(origin: .zero, size: canvas))
    let bloom = CGGradient(colorsSpace: space, colors: [c(139, 108, 255, 0.34), c(255, 79, 154, 0.12), c(10, 9, 18, 0)] as CFArray,
                           locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: cx, y: y(iconY)), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: y(iconY)), endRadius: 420, options: [])
    let top = CGGradient(colorsSpace: space, colors: [c(255, 255, 255, 0.05), c(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(top, start: CGPoint(x: 0, y: y(0)), end: CGPoint(x: 0, y: y(120)), options: [])

    // Brand row.
    let word = NSAttributedString(string: "Blinko", attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.white, .kern: -1.0])
    let rowW = 42 + 12 + word.size().width
    logo?.draw(in: NSRect(x: cx - rowW / 2, y: y(70), width: 42, height: 42))
    word.draw(at: NSPoint(x: cx - rowW / 2 + 54, y: y(64)))
    let tag = NSAttributedString(string: "Your notch, alive.", attributes: [
        .font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.55)])
    tag.draw(at: NSPoint(x: cx - tag.size().width / 2, y: y(92)))

    // Icon wells.
    for x in [appX, appsX] {
        let well = NSBezierPath(roundedRect: NSRect(x: x - 74, y: y(iconY) - 74, width: 148, height: 148), xRadius: 34, yRadius: 34)
        NSColor(white: 1, alpha: 0.045).setFill(); well.fill()
        NSColor(white: 1, alpha: 0.08).setStroke(); well.lineWidth = 1; well.stroke()
    }

    // Label chips: Finder draws icon names in dark grey (light mode) or white (dark mode) and
    // won't let us recolour them, so a mid-tone chip keeps both readable on the dark art.
    let labelY: CGFloat = 276
    for (x, w) in [(appX, CGFloat(78)), (appsX, CGFloat(112))] {
        let chip = NSBezierPath(roundedRect: NSRect(x: x - w / 2, y: y(labelY) - 10, width: w, height: 20), xRadius: 10, yRadius: 10)
        NSColor(srgbRed: 0.62, green: 0.60, blue: 0.68, alpha: 0.85).setFill(); chip.fill()
    }

    // Arrow.
    let ay = y(iconY)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: appX + 92, y: ay)); path.line(to: NSPoint(x: appsX - 98, y: ay))
    path.lineWidth = 3; path.lineCapStyle = .round
    path.setLineDash([2, 9], count: 2, phase: 0)
    NSColor(white: 1, alpha: 0.5).setStroke(); path.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: appsX - 102, y: ay + 11)); head.line(to: NSPoint(x: appsX - 88, y: ay)); head.line(to: NSPoint(x: appsX - 102, y: ay - 11))
    head.lineWidth = 3.5; head.lineCapStyle = .round; head.lineJoinStyle = .round
    NSColor(srgbRed: 1, green: 0.42, blue: 0.68, alpha: 1).setStroke(); head.stroke()

    // Instruction, tip, footer (Finder draws the icon labels at ≈ iconY + 80).
    let drag = NSAttributedString(string: "Drag Blinko to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.92)])
    drag.draw(at: NSPoint(x: cx - drag.size().width / 2, y: y(318)))
    let tip = NSAttributedString(string: "First launch: if macOS asks, open System Settings › Privacy & Security and click “Open Anyway”.",
                                 attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular),
                                              .foregroundColor: NSColor(white: 1, alpha: 0.45)])
    tip.draw(at: NSPoint(x: cx - tip.size().width / 2, y: y(344)))
    let footer = NSAttributedString(string: (version.isEmpty ? "" : "Version \(version)  ·  ") + "Designed by OptimaGeeks", attributes: [
        .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.32), .kern: 0.3])
    footer.draw(at: NSPoint(x: cx - footer.size().width / 2, y: y(378)))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try! render(scale: 1).write(to: outDir.appendingPathComponent("bg.png"))
try! render(scale: 2).write(to: outDir.appendingPathComponent("bg@2x.png"))
print("ok")
