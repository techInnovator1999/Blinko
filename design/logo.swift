// Blinko logo renderer. Usage: swift design/logo.swift <variant> <out.png> [size]
import AppKit

let args = CommandLine.arguments
let variant = args.count > 1 ? args[1] : "notch-eye"
let out = args.count > 2 ? args[2] : "logo.png"
let px = args.count > 3 ? Int(args[3])! : 1024
let S = CGFloat(px)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// macOS icon grid: 824/1024 tile, continuous corners.
let inset = S * 100 / 1024
let tile = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius = tile.width * 0.2237
let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow under the tile (Big Sur style)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(20, 18, 30)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()

func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func radial(_ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

let cx = tile.midX

/// Island silhouette hanging from the tile's top edge: concave ears + rounded bottom.
func islandPath(width w: CGFloat, height h: CGFloat, ear e: CGFloat, bottomRadius b: CGFloat, top: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let l = cx - w / 2, r = cx + w / 2, bottom = top - h
    p.move(to: CGPoint(x: l - e, y: top))
    p.addQuadCurve(to: CGPoint(x: l, y: top - e), control: CGPoint(x: l, y: top))
    p.addLine(to: CGPoint(x: l, y: bottom + b))
    p.addCurve(to: CGPoint(x: l + b, y: bottom), control1: CGPoint(x: l, y: bottom + b * 0.45), control2: CGPoint(x: l + b * 0.45, y: bottom))
    p.addLine(to: CGPoint(x: r - b, y: bottom))
    p.addCurve(to: CGPoint(x: r, y: bottom + b), control1: CGPoint(x: r - b * 0.45, y: bottom), control2: CGPoint(x: r, y: bottom + b * 0.45))
    p.addLine(to: CGPoint(x: r, y: top - e))
    p.addQuadCurve(to: CGPoint(x: r + e, y: top), control: CGPoint(x: r, y: top))
    p.closeSubpath()
    return p
}

/// A closed-eye "blink": lower lid arc with lashes.
func blink(center c: CGPoint, width w: CGFloat, color: CGColor, lineWidth: CGFloat, lashes: Bool) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x - w / 2, y: c.y))
    p.addQuadCurve(to: CGPoint(x: c.x + w / 2, y: c.y), control: CGPoint(x: c.x, y: c.y - w * 0.42))
    ctx.addPath(p)
    ctx.setStrokeColor(color); ctx.setLineWidth(lineWidth); ctx.setLineCap(.round); ctx.strokePath()
    guard lashes else { return }
    for t in [0.22, 0.5, 0.78] as [CGFloat] {
        // Point on the quad curve and its outward normal.
        let x0 = c.x - w / 2, x2 = c.x + w / 2, cy1 = c.y - w * 0.42
        let px = (1 - t) * (1 - t) * x0 + 2 * (1 - t) * t * c.x + t * t * x2
        let py = (1 - t) * (1 - t) * c.y + 2 * (1 - t) * t * cy1 + t * t * c.y
        let dx = 2 * (1 - t) * (c.x - x0) + 2 * t * (x2 - c.x)
        let dy = 2 * (1 - t) * (cy1 - c.y) + 2 * t * (c.y - cy1)
        let len = hypot(dx, dy)
        let nx = dy / len, ny = -dx / len
        let lash = w * 0.17
        ctx.move(to: CGPoint(x: px + nx * lineWidth * 0.4, y: py + ny * lineWidth * 0.4))
        ctx.addLine(to: CGPoint(x: px + nx * lash, y: py + ny * lash))
    }
    ctx.strokePath()
}

switch variant {
case "notch-eye":
    // Midnight → violet → hot pink background
    linear([rgb(14, 12, 28), rgb(58, 28, 110), rgb(255, 72, 130)],
           from: CGPoint(x: tile.minX, y: tile.maxY), to: CGPoint(x: tile.maxX, y: tile.minY))
    radial([rgb(255, 120, 170, 0.55), rgb(255, 120, 170, 0)], center: CGPoint(x: cx, y: tile.maxY - tile.height * 0.32), radius: tile.width * 0.55)
    // The island
    let w = tile.width * 0.56, h = tile.height * 0.30
    let island = islandPath(width: w, height: h, ear: tile.width * 0.05, bottomRadius: h * 0.48, top: tile.maxY + 1)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.02), blur: S * 0.06, color: rgb(10, 0, 30, 0.7))
    ctx.addPath(island); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()
    // Blink inside the island
    blink(center: CGPoint(x: cx, y: tile.maxY - h * 0.46), width: w * 0.42, color: rgb(255, 255, 255), lineWidth: S * 0.026, lashes: true)

case "eye-pill":
    linear([rgb(10, 10, 16), rgb(34, 30, 52)], from: CGPoint(x: cx, y: tile.maxY), to: CGPoint(x: cx, y: tile.minY))
    radial([rgb(120, 90, 255, 0.45), rgb(120, 90, 255, 0)], center: CGPoint(x: cx, y: tile.midY), radius: tile.width * 0.6)
    // Pill
    let pw = tile.width * 0.7, ph = tile.width * 0.3
    let pill = CGRect(x: cx - pw / 2, y: tile.midY - ph / 2, width: pw, height: ph)
    ctx.addPath(CGPath(roundedRect: pill, cornerWidth: ph / 2, cornerHeight: ph / 2, transform: nil))
    ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: pill.insetBy(dx: S * 0.002, dy: S * 0.002), cornerWidth: ph / 2, cornerHeight: ph / 2, transform: nil))
    ctx.setStrokeColor(rgb(255, 255, 255, 0.14)); ctx.setLineWidth(S * 0.004); ctx.strokePath()
    // Iris: gradient ring + pupil highlight
    let ir = ph * 0.32
    let ic = CGPoint(x: cx, y: pill.midY)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: ic.x - ir, y: ic.y - ir, width: ir * 2, height: ir * 2)); ctx.clip()
    linear([rgb(80, 220, 255), rgb(150, 90, 255), rgb(255, 80, 160)], from: CGPoint(x: ic.x - ir, y: ic.y + ir), to: CGPoint(x: ic.x + ir, y: ic.y - ir))
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: ic.x - ir * 0.45, y: ic.y - ir * 0.45, width: ir * 0.9, height: ir * 0.9))
    ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: ic.x + ir * 0.12, y: ic.y + ir * 0.12, width: ir * 0.3, height: ir * 0.3))
    ctx.setFillColor(rgb(255, 255, 255, 0.9)); ctx.fillPath()

case "notch-iris":
    linear([rgb(8, 8, 14), rgb(26, 24, 44)], from: CGPoint(x: cx, y: tile.maxY), to: CGPoint(x: cx, y: tile.minY))
    radial([rgb(110, 80, 255, 0.5), rgb(110, 80, 255, 0)], center: CGPoint(x: cx, y: tile.maxY - tile.height * 0.25), radius: tile.width * 0.6)
    let w = tile.width * 0.62, h = tile.height * 0.34
    let island = islandPath(width: w, height: h, ear: tile.width * 0.05, bottomRadius: h * 0.5, top: tile.maxY + 1)
    ctx.addPath(island); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    // Rim light along the island's bottom
    ctx.addPath(island); ctx.setStrokeColor(rgb(255, 255, 255, 0.10)); ctx.setLineWidth(S * 0.004); ctx.strokePath()
    // Iris peeking out of the island (half-open eye)
    let ir = h * 0.3
    let ic = CGPoint(x: cx, y: tile.maxY - h * 0.5)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: ic.x - ir, y: ic.y - ir, width: ir * 2, height: ir * 2)); ctx.clip()
    linear([rgb(90, 230, 255), rgb(140, 90, 255), rgb(255, 70, 150)], from: CGPoint(x: ic.x - ir, y: ic.y + ir), to: CGPoint(x: ic.x + ir, y: ic.y - ir))
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: ic.x - ir * 0.42, y: ic.y - ir * 0.42, width: ir * 0.84, height: ir * 0.84))
    ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: ic.x + ir * 0.1, y: ic.y + ir * 0.12, width: ir * 0.28, height: ir * 0.28))
    ctx.setFillColor(rgb(255, 255, 255, 0.92)); ctx.fillPath()
    // Wordless "b" hint: soft reflection line on tile bottom
    radial([rgb(255, 70, 150, 0.35), rgb(255, 70, 150, 0)], center: CGPoint(x: cx, y: tile.minY), radius: tile.width * 0.5)

case "lid":
    // Indigo night with a magenta bloom: the eye "lights up" the tile.
    linear([rgb(28, 22, 64), rgb(18, 14, 38), rgb(10, 8, 22)],
           from: CGPoint(x: cx, y: tile.maxY), to: CGPoint(x: cx, y: tile.minY))
    let w = tile.width * 0.60, h = tile.height * 0.31
    let lidBottom = tile.maxY - h
    let ir = tile.width * 0.20
    // ~62 % of the iris shows below the lid: a blink in progress.
    let ic = CGPoint(x: cx, y: lidBottom - ir * 0.24)
    radial([rgb(255, 80, 170, 0.62), rgb(120, 90, 255, 0.28), rgb(120, 90, 255, 0)],
           center: CGPoint(x: cx, y: ic.y - ir * 0.3), radius: tile.width * 0.66)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: ic.x - ir, y: ic.y - ir, width: ir * 2, height: ir * 2)); ctx.clip()
    linear([rgb(80, 235, 255), rgb(140, 105, 255), rgb(255, 90, 170)],
           from: CGPoint(x: ic.x - ir, y: ic.y - ir * 0.6), to: CGPoint(x: ic.x + ir, y: ic.y + ir * 0.4))
    // Fine radial fibres
    ctx.setStrokeColor(rgb(255, 255, 255, 0.10)); ctx.setLineWidth(S * 0.002)
    for i in 0..<36 {
        let t = CGFloat(i) / 36 * .pi * 2
        ctx.move(to: CGPoint(x: ic.x + cos(t) * ir * 0.42, y: ic.y + sin(t) * ir * 0.42))
        ctx.addLine(to: CGPoint(x: ic.x + cos(t) * ir * 0.95, y: ic.y + sin(t) * ir * 0.95))
    }
    ctx.strokePath()
    radial([rgb(0, 0, 0, 0), rgb(0, 0, 0, 0), rgb(10, 0, 40, 0.45)], center: ic, radius: ir)
    ctx.restoreGState()
    let pr = ir * 0.36
    ctx.addEllipse(in: CGRect(x: ic.x - pr, y: ic.y - pr, width: pr * 2, height: pr * 2))
    ctx.setFillColor(rgb(6, 4, 14)); ctx.fillPath()
    // Catch-light in the visible upper area, just below the lid.
    let cl = pr * 0.5
    ctx.addEllipse(in: CGRect(x: ic.x + pr * 0.35, y: ic.y + pr * 0.05, width: cl, height: cl))
    ctx.setFillColor(rgb(255, 255, 255, 0.95)); ctx.fillPath()
    // Island = eyelid
    let island = islandPath(width: w, height: h, ear: tile.width * 0.06, bottomRadius: h * 0.46, top: tile.maxY + 1)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.01), blur: S * 0.03, color: rgb(0, 0, 0, 0.9))
    ctx.addPath(island); ctx.setFillColor(rgb(0, 0, 0)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(island); ctx.clip()
    linear([rgb(255, 255, 255, 0), rgb(255, 255, 255, 0.13)],
           from: CGPoint(x: cx, y: lidBottom + h * 0.35), to: CGPoint(x: cx, y: lidBottom))
    ctx.restoreGState()

default: break
}

// Glass sheen on the tile
if variant != "lid" { linear([rgb(255, 255, 255, 0.10), rgb(255, 255, 255, 0)], from: CGPoint(x: cx, y: tile.maxY), to: CGPoint(x: cx, y: tile.midY)) }
ctx.restoreGState()
// Hairline tile border
ctx.addPath(tilePath); ctx.setStrokeColor(rgb(255, 255, 255, 0.08)); ctx.setLineWidth(S * 0.003); ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
