import AppKit

/// Layout of the static parts of the Lamplight room, in view points (origin bottom-left).
struct RoomLayout {
    var size: CGSize
    var deskBack: CGFloat      // y of the desk's back edge, where it meets the wall
    var lampBase: CGPoint      // where the lamp stands on the desk
    var lampHeight: CGFloat
    var frameRect: CGRect      // outer edge of the picture frame on the wall
}

extension Art {
    /// Paints the room once per screen size: a wall lit by a globe lamp, a framed
    /// print with a soft backlight, and a walnut desk with grain. Everything that
    /// moves or changes with the music is a live layer drawn on top of this.
    static func room(_ L: RoomLayout, scale: CGFloat) -> CGImage {
        let W = L.size.width, H = L.size.height
        return render(width: Int(W * scale), height: Int(H * scale)) { ctx in
            ctx.scaleBy(x: scale, y: scale)
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            func grad(_ stops: [(NSColor, CGFloat)]) -> CGGradient {
                CGGradient(colorsSpace: space, colors: stops.map { $0.0.cgColor } as CFArray,
                           locations: stops.map { $0.1 })!
            }
            func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
                NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                        blue: CGFloat(v & 0xFF) / 255, alpha: a)
            }
            var seed: UInt64 = 0x2545F4914F6CDD1D
            func rand() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }

            let globe = CGPoint(x: L.lampBase.x, y: L.lampBase.y + L.lampHeight * 0.72)
            let globeR = L.lampHeight * 0.24

            // Wall: dark umber, washed by the lamp from the left.
            ctx.setFillColor(hex(0x24150E).cgColor)
            ctx.fill(CGRect(x: 0, y: L.deskBack, width: W, height: H - L.deskBack))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: L.deskBack, width: W, height: H - L.deskBack))
            ctx.drawRadialGradient(grad([(hex(0xFFC48A, 0.95), 0), (hex(0xE8925A, 0.55), 0.25),
                                         (hex(0x9A5634, 0.25), 0.6), (hex(0x24150E, 0), 1)]),
                                   startCenter: globe, startRadius: 0, endCenter: globe,
                                   endRadius: W * 0.95, options: [])
            // Soft warm light falling from above the frame.
            let fc = CGPoint(x: L.frameRect.midX, y: L.frameRect.midY)
            ctx.drawRadialGradient(grad([(hex(0xFFB070, 0.55), 0), (hex(0xFFB070, 0), 1)]),
                                   startCenter: fc, startRadius: L.frameRect.width * 0.3, endCenter: fc,
                                   endRadius: L.frameRect.width * 1.25, options: [])
            ctx.restoreGState()

            // Frame: dark wood with a cream mat. The print itself is a live layer.
            let f = L.frameRect
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -f.width * 0.03), blur: f.width * 0.08,
                          color: NSColor(white: 0, alpha: 0.6).cgColor)
            ctx.setFillColor(hex(0x2A1A10).cgColor)
            ctx.fill(f)
            ctx.restoreGState()
            ctx.setFillColor(hex(0xE9DDC8).cgColor)
            ctx.fill(f.insetBy(dx: f.width * 0.06, dy: f.width * 0.06))
            ctx.setStrokeColor(NSColor(white: 1, alpha: 0.08).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(f.insetBy(dx: 0.5, dy: 0.5))

            // Desk: walnut, darker toward the front, with grain.
            let desk = CGRect(x: 0, y: 0, width: W, height: L.deskBack)
            ctx.saveGState()
            ctx.clip(to: desk)
            ctx.drawLinearGradient(grad([(hex(0x6A3A1F), 0), (hex(0x3A1D0E), 0.6), (hex(0x1E0E06), 1)]),
                                   start: CGPoint(x: 0, y: L.deskBack), end: .zero, options: [])
            for _ in 0..<260 {
                let y = rand() * L.deskBack
                let amp = 1 + rand() * 4, freq = 0.002 + rand() * 0.006, phase = rand() * 6.28
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x <= W {
                    path.addLine(to: CGPoint(x: x, y: y + amp * sin(x * freq + phase)))
                    x += 12
                }
                let dark = rand() < 0.7
                ctx.setStrokeColor(dark ? NSColor(white: 0, alpha: 0.04 + rand() * 0.08).cgColor
                                        : hex(0xC07A45, 0.03 + rand() * 0.05).cgColor)
                ctx.setLineWidth(0.5 + rand() * 1.8)
                ctx.addPath(path)
                ctx.strokePath()
            }
            // Pool of lamplight on the desk.
            ctx.saveGState()
            ctx.translateBy(x: L.lampBase.x, y: L.lampBase.y)
            ctx.scaleBy(x: 1, y: 0.35)
            ctx.drawRadialGradient(grad([(hex(0xFFB878, 0.45), 0), (hex(0xFFB878, 0), 1)]),
                                   startCenter: .zero, startRadius: 0, endCenter: .zero,
                                   endRadius: W * 0.45, options: [])
            ctx.restoreGState()
            ctx.restoreGState()

            // Back edge of the desk catches the light.
            ctx.setFillColor(hex(0xFFC890, 0.22).cgColor)
            ctx.fill(CGRect(x: 0, y: L.deskBack - 1, width: W, height: 1.5))
            ctx.setFillColor(NSColor(white: 0, alpha: 0.35).cgColor)
            ctx.fill(CGRect(x: 0, y: L.deskBack + 0.5, width: W, height: 2))

            // Globe lamp: brass foot, thin stem, opal glass sphere.
            let lh = L.lampHeight, bx = L.lampBase.x, by = L.lampBase.y
            ctx.saveGState()
            ctx.translateBy(x: bx, y: by)
            ctx.scaleBy(x: 1, y: 0.3)
            ctx.drawRadialGradient(grad([(NSColor(white: 0, alpha: 0.55), 0), (NSColor(white: 0, alpha: 0), 1)]),
                                   startCenter: .zero, startRadius: 0, endCenter: .zero,
                                   endRadius: lh * 0.32, options: [])
            ctx.restoreGState()
            let foot = CGMutablePath()
            foot.move(to: CGPoint(x: bx - lh * 0.17, y: by))
            foot.addLine(to: CGPoint(x: bx + lh * 0.17, y: by))
            foot.addLine(to: CGPoint(x: bx + lh * 0.05, y: by + lh * 0.07))
            foot.addLine(to: CGPoint(x: bx - lh * 0.05, y: by + lh * 0.07))
            foot.closeSubpath()
            ctx.saveGState()
            ctx.addPath(foot)
            ctx.clip()
            ctx.drawLinearGradient(grad([(hex(0x5A4020), 0), (hex(0xD9B070), 0.35), (hex(0x8A6330), 1)]),
                                   start: CGPoint(x: bx - lh * 0.17, y: by), end: CGPoint(x: bx + lh * 0.17, y: by),
                                   options: [])
            ctx.restoreGState()
            ctx.setFillColor(hex(0xB08850).cgColor)
            ctx.fill(CGRect(x: bx - lh * 0.012, y: by + lh * 0.07, width: lh * 0.024, height: lh * 0.45))

            ctx.drawRadialGradient(grad([(hex(0xFFD9A0, 0.55), 0), (hex(0xFFB060, 0), 1)]),
                                   startCenter: globe, startRadius: globeR * 0.9, endCenter: globe,
                                   endRadius: globeR * 3.2, options: [])
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: globe.x - globeR, y: globe.y - globeR, width: 2 * globeR, height: 2 * globeR))
            ctx.clip()
            let hot = CGPoint(x: globe.x - globeR * 0.15, y: globe.y + globeR * 0.1)
            ctx.drawRadialGradient(grad([(hex(0xFFFBF0), 0), (hex(0xFFE2B0), 0.35), (hex(0xF2A865), 0.85),
                                         (hex(0xC9783E), 1)]),
                                   startCenter: hot, startRadius: 0, endCenter: globe, endRadius: globeR,
                                   options: [.drawsAfterEndLocation])
            ctx.restoreGState()

            // Vignette.
            let mid = CGPoint(x: W / 2, y: H / 2)
            ctx.drawRadialGradient(grad([(NSColor(white: 0, alpha: 0), 0), (NSColor(white: 0, alpha: 0.12), 0.6),
                                         (NSColor(white: 0, alpha: 0.55), 1)]),
                                   startCenter: mid, startRadius: 0, endCenter: mid,
                                   endRadius: hypot(W, H) / 2, options: [])
        }
    }
}
