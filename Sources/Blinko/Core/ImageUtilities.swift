import AppKit
import CoreImage

extension NSImage {
    /// Re-renders into a small bitmap so SwiftUI never scales a multi-MB artwork every frame.
    func downsampled(to maxPixel: CGFloat) -> NSImage {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let scale = min(1, maxPixel / CGFloat(max(cg.width, cg.height)))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard scale < 1,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return self }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return self }
        return NSImage(cgImage: out, size: NSSize(width: w, height: h))
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Pre-blurred copy for the ambient glow, rendered once (off-main) instead of a live
    /// SwiftUI blur that re-convolves on the CPU whenever the view redraws.
    func blurredGlow(radius: CGFloat = 14) -> NSImage? {
        guard let cg = downsampled(to: 96).cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Not clamped: the blur bleeds into transparent padding, giving a soft halo edge.
        let input = CIImage(cgImage: cg)
        guard let blurred = CIFilter(name: "CIGaussianBlur",
                                     parameters: [kCIInputImageKey: input, kCIInputRadiusKey: radius])?.outputImage
        else { return nil }
        let pad = radius * 2
        let rect = CGRect(x: -pad, y: -pad, width: CGFloat(cg.width) + pad * 2, height: CGFloat(cg.height) + pad * 2)
        guard let out = Self.ciContext.createCGImage(blurred, from: rect) else { return nil }
        return NSImage(cgImage: out, size: rect.size)
    }

    /// Average colour of the artwork, lifted so it reads well on pure black.
    func dominantAccent() -> NSColor {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let base = NSColor(srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                           blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 { return NSColor(white: 0.92, alpha: 1) } // greyscale art: stay neutral
        return NSColor(hue: h, saturation: min(max(s * 1.15, 0.25), 0.85), brightness: max(b, 0.82), alpha: 1)
    }
}
