import AppKit

/// Procedurally drawn artwork: the record itself, plus the default label and
/// sleeve shown when nothing is playing. Nothing here is a bundled asset.
enum Art {
    private static var discCache: [Int: CGImage] = [:]

    static func render(width: Int, height: Int, _ draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()!
    }

    /// Black vinyl with fine grooves, track gaps and a rim, at `diameter` pixels.
    static func disc(diameter: Int) -> CGImage {
        if let cached = discCache[diameter] { return cached }
        let img = render(width: diameter, height: diameter) { ctx in
            let s = CGFloat(diameter) / 2
            let c = CGPoint(x: s, y: s)
            func ring(_ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r) }

            ctx.setFillColor(NSColor(white: 0.055, alpha: 1).cgColor)
            ctx.fillEllipse(in: ring(s))

            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rand() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }

            ctx.setLineWidth(max(0.6, s * 0.0022))
            var r = s * 0.36
            while r < s * 0.975 {
                ctx.setStrokeColor(NSColor(white: 1, alpha: 0.018 + 0.05 * rand()).cgColor)
                ctx.strokeEllipse(in: ring(r))
                r += max(1.2, s * 0.0055)
            }

            ctx.setStrokeColor(NSColor(white: 0, alpha: 0.85).cgColor)
            ctx.setLineWidth(s * 0.007)
            for f: CGFloat in [0.47, 0.585, 0.70, 0.815, 0.90] {
                ctx.strokeEllipse(in: ring(s * f))
            }

            ctx.setStrokeColor(NSColor(white: 0.25, alpha: 1).cgColor)
            ctx.setLineWidth(s * 0.01)
            ctx.strokeEllipse(in: ring(s * 0.993))
        }
        discCache[diameter] = img
        return img
    }

    /// The paper label used when there is no album art: red, with text so the spin reads.
    static let defaultLabel: CGImage = render(width: 512, height: 512) { ctx in
        let rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        ctx.setFillColor(NSColor(red: 0.62, green: 0.13, blue: 0.10, alpha: 1).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.25).cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: rect.insetBy(dx: 30, dy: 30))
        ctx.strokeEllipse(in: rect.insetBy(dx: 150, dy: 150))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        func text(_ s: String, size: CGFloat, y: CGFloat, weight: NSFont.Weight) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor(white: 1, alpha: 0.92),
                .paragraphStyle: style,
                .kern: size * 0.18,
            ]
            (s as NSString).draw(in: CGRect(x: 0, y: y, width: 512, height: size * 1.4), withAttributes: attrs)
        }
        text("VINYL", size: 54, y: 380, weight: .heavy)
        text("SIDE A  ·  33⅓ RPM", size: 22, y: 90, weight: .semibold)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The sleeve shown in Studio when there is no album art.
    static let defaultSleeve: CGImage = render(width: 1024, height: 1024) { ctx in
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [NSColor(red: 0.10, green: 0.22, blue: 0.24, alpha: 1).cgColor,
                      NSColor(red: 0.03, green: 0.06, blue: 0.07, alpha: 1).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
        ctx.setStrokeColor(NSColor(red: 0.95, green: 0.62, blue: 0.30, alpha: 0.55).cgColor)
        for i in 0..<9 {
            ctx.setLineWidth(i == 0 ? 6 : 2)
            let r = CGFloat(120 + i * 42)
            ctx.strokeEllipse(in: CGRect(x: 600 - r, y: 600 - r, width: 2 * r, height: 2 * r))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .black),
            .foregroundColor: NSColor(white: 0.95, alpha: 1),
            .kern: 10,
        ]
        ("VINYL" as NSString).draw(at: CGPoint(x: 70, y: 80), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Average colour of an image, lifted so it still glows on a dark background.
    static func glowColor(of image: CGImage?) -> NSColor {
        guard let image else { return NSColor(red: 0.85, green: 0.35, blue: 0.25, alpha: 1) }
        let px = render(width: 1, height: 1) { ctx in
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let data = px.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return .systemPink }
        let base = NSColor(red: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255,
                           blue: CGFloat(p[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1, s * 1.3), brightness: max(b, 0.6), alpha: 1)
    }
}
