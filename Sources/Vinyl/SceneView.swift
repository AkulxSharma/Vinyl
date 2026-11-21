import AppKit
import QuartzCore

/// Where things go in the current scene, in view coordinates (origin bottom-left).
private struct Geometry {
    var S: CGFloat = 0
    var R: CGFloat = 0
    /// Record position while playing and while paused (they differ only in Studio,
    /// where the record slides back into its sleeve on pause).
    var recordOut = CGPoint.zero
    var recordIn = CGPoint.zero
    var infoRect = CGRect.zero
    var infoAlign: CATextLayerAlignmentMode = .center
    var maxStack = 6
    /// Centre, side length and rotation (radians) of the i-th recently played cover.
    var stackSlot: (Int) -> (CGPoint, CGFloat, CGFloat) = { _ in (.zero, 0, 0) }
}

/// Renders one desktop scene with Core Animation. The record spins on the GPU via a
/// repeating rotation animation; pausing freezes the layer's clock, so it costs no CPU.
final class SceneView: NSView {
    private let px: CGFloat
    private let root = CALayer()

    private var recordGroup = CALayer()
    private var rotor = CALayer()
    private var label = CALayer()
    private var sleeve: CALayer?
    private var arm: CALayer?
    private var lamp: CALayer?
    private var glow: CAGradientLayer?
    private let titleLayer = CATextLayer()
    private let artistLayer = CATextLayer()
    private let barTrack = CALayer()
    private let barFill = CALayer()
    private var stackLayers: [String: CALayer] = [:]

    private var geo = Geometry()
    private var spinPaused = false
    private var shownArtKey: String?

    init(frame: NSRect, backingScale: CGFloat) {
        px = backingScale
        super.init(frame: frame)
        layer = root
        wantsLayer = true
        root.contentsScale = px
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
                                               name: Settings.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged),
                                               name: NowPlaying.didChange, object: nil)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Building

    @objc private func rebuild() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        stackLayers.removeAll()
        sleeve = nil; arm = nil; lamp = nil; glow = nil
        shownArtKey = nil
        spinPaused = false

        let st = Settings.shared
        geo = Geometry()
        geo.S = min(bounds.width, bounds.height) * (st.transparent ? st.overlaySize.factor : st.framing.factor)

        switch st.scene {
        case .deck: buildDeck(transparent: st.transparent)
        case .studio: buildStudio(transparent: st.transparent)
        case .midnight: buildMidnight(transparent: st.transparent)
        }
        buildInfo(visible: st.showInfo, shadowed: st.transparent)
        CATransaction.commit()

        apply(animated: false)
    }

    private func add<T: CALayer>(_ l: T, z: CGFloat = 0) -> T {
        l.contentsScale = px
        l.zPosition = z
        root.addSublayer(l)
        return l
    }

    private func gradient(_ frame: CGRect, _ colors: [NSColor], start: CGPoint = CGPoint(x: 0.5, y: 1),
                          end: CGPoint = CGPoint(x: 0.5, y: 0), type: CAGradientLayerType = .axial) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.frame = frame
        g.colors = colors.map(\.cgColor)
        g.startPoint = start
        g.endPoint = end
        g.type = type
        return g
    }

    private func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }

    private func makeRecord(center: CGPoint, R: CGFloat, z: CGFloat) {
        let g = CALayer()
        g.bounds = CGRect(x: 0, y: 0, width: 2 * R, height: 2 * R)
        g.position = center
        g.zPosition = z
        g.shadowColor = NSColor.black.cgColor
        g.shadowOpacity = 0.6
        g.shadowRadius = R * 0.07
        g.shadowOffset = CGSize(width: 0, height: -R * 0.03)
        g.shadowPath = CGPath(ellipseIn: g.bounds, transform: nil)

        let r = CALayer()
        r.frame = g.bounds
        r.contents = Art.disc(diameter: Int(ceil(2 * R * px)))
        r.contentsScale = px

        let lr = R * 0.34
        let lab = CALayer()
        lab.bounds = CGRect(x: 0, y: 0, width: 2 * lr, height: 2 * lr)
        lab.position = CGPoint(x: R, y: R)
        lab.cornerRadius = lr
        lab.masksToBounds = true
        lab.contentsGravity = .resizeAspectFill
        lab.contents = Art.defaultLabel
        r.addSublayer(lab)
        g.addSublayer(r)

        // Light reflection stays still while the record turns underneath it.
        let w = { (a: CGFloat) in NSColor(white: 1, alpha: a) }
        let sheen = gradient(g.bounds, [w(0), w(0.10), w(0), w(0), w(0), w(0.08), w(0), w(0)],
                             start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 1), type: .conic)
        sheen.cornerRadius = R
        sheen.masksToBounds = true
        g.addSublayer(sheen)

        let hr = R * 0.022
        let hole = CALayer()
        hole.frame = CGRect(x: R - hr, y: R - hr, width: 2 * hr, height: 2 * hr)
        hole.cornerRadius = hr
        hole.backgroundColor = NSColor(white: 0.8, alpha: 1).cgColor
        g.addSublayer(hole)

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 1.8 // 33⅓ rpm
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        r.add(spin, forKey: "spin")

        _ = add(g, z: z)
        recordGroup = g
        rotor = r
        label = lab
    }

    /// Deck: a turntable on a wooden table with a tonearm, and played records piled beside it.
    private func buildDeck(transparent: Bool) {
        let S = geo.S, c = CGPoint(x: bounds.midX, y: bounds.midY)
        let plinth = CGRect(x: c.x - 0.95 * S, y: c.y - 0.425 * S, width: 1.3 * S, height: 0.95 * S)

        if !transparent {
            _ = add(gradient(bounds, [hex(0x2B231E), hex(0x14100D)]), z: -100)
            let tableTop = plinth.minY + 0.12 * S
            let table = CGRect(x: 0, y: 0, width: bounds.width, height: tableTop)
            _ = add(gradient(table, [hex(0x4B3424), hex(0x1E140D)]), z: -99)
            let edge = CALayer()
            edge.frame = CGRect(x: 0, y: tableTop - 1, width: bounds.width, height: 1.5)
            edge.backgroundColor = NSColor(white: 1, alpha: 0.07).cgColor
            _ = add(edge, z: -98)
            let spot = gradient(CGRect(x: c.x - 1.6 * S, y: c.y - 1.2 * S, width: 3.2 * S, height: 2.6 * S),
                                [NSColor(white: 1, alpha: 0.07), NSColor(white: 1, alpha: 0)],
                                start: CGPoint(x: 0.5, y: 0.6), end: CGPoint(x: 1, y: 1), type: .radial)
            _ = add(spot, z: -97)
        }

        let p = gradient(plinth, [hex(0x323235), hex(0x18181A)])
        p.cornerRadius = 0.04 * S
        p.borderWidth = 1
        p.borderColor = NSColor(white: 1, alpha: 0.07).cgColor
        p.shadowOpacity = 0.6
        p.shadowRadius = 0.04 * S
        p.shadowOffset = CGSize(width: 0, height: -0.02 * S)
        _ = add(p, z: -10)

        let R = 0.4 * S
        let rc = CGPoint(x: plinth.minX + 0.15 * S + R, y: plinth.midY)
        geo.R = R
        geo.recordOut = rc
        geo.recordIn = rc

        let pr = R * 1.05
        let platter = gradient(CGRect(x: rc.x - pr, y: rc.y - pr, width: 2 * pr, height: 2 * pr),
                               [hex(0x9A9A9E), hex(0x5C5C60), hex(0xB4B4B8), hex(0x5C5C60), hex(0x9A9A9E)],
                               start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 1), type: .conic)
        platter.cornerRadius = pr
        platter.masksToBounds = true
        _ = add(platter, z: -5)

        makeRecord(center: rc, R: R, z: 0)

        // Tonearm: pivots at the top right of the plinth; swings onto the record when playing.
        let pivot = CGPoint(x: rc.x + 1.15 * R, y: rc.y + 0.85 * R)
        let br = 0.12 * R
        let base = gradient(CGRect(x: pivot.x - br, y: pivot.y - br, width: 2 * br, height: 2 * br),
                            [hex(0xD0D0D4), hex(0x6A6A70)])
        base.cornerRadius = br
        _ = add(base, z: 19)

        let L = 1.6 * R, aw = 0.2 * R
        let a = CAShapeLayer()
        a.bounds = CGRect(x: 0, y: 0, width: aw, height: L)
        a.anchorPoint = CGPoint(x: 0.5, y: 1)
        a.position = pivot
        let path = CGMutablePath()
        path.move(to: CGPoint(x: aw / 2, y: L + 0.16 * R))
        path.addLine(to: CGPoint(x: aw / 2, y: 0.2 * R))
        a.path = path
        a.strokeColor = NSColor(white: 0.85, alpha: 1).cgColor
        a.lineWidth = 0.035 * R
        a.lineCap = .round
        a.fillColor = nil
        let head = CALayer()
        head.frame = CGRect(x: aw / 2 - 0.055 * R, y: 0, width: 0.11 * R, height: 0.22 * R)
        head.backgroundColor = NSColor(white: 0.7, alpha: 1).cgColor
        head.cornerRadius = 0.015 * R
        a.addSublayer(head)
        let weight = CALayer()
        weight.frame = CGRect(x: aw / 2 - 0.07 * R, y: L + 0.14 * R, width: 0.14 * R, height: 0.2 * R)
        weight.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        weight.cornerRadius = 0.02 * R
        a.addSublayer(weight)
        a.shadowOpacity = 0.5
        a.shadowRadius = 0.02 * S
        a.shadowOffset = CGSize(width: 0.01 * S, height: -0.015 * S)
        arm = add(a, z: 20)

        let lr = 0.022 * S
        let l = CALayer()
        l.frame = CGRect(x: plinth.minX + 0.07 * S, y: plinth.minY + 0.07 * S, width: 2 * lr, height: 2 * lr)
        l.cornerRadius = lr
        l.shadowRadius = 0.025 * S
        l.shadowOffset = .zero
        lamp = add(l, z: 21)

        geo.infoRect = CGRect(x: plinth.minX, y: plinth.minY - 0.26 * S, width: plinth.width, height: 0.22 * S)
        geo.infoAlign = .left
        geo.maxStack = 7
        let C = 0.44 * S
        let stackBase = CGPoint(x: plinth.maxX + 0.08 * S + C / 2, y: plinth.minY + C / 2 + 0.16 * S)
        geo.stackSlot = { i in
            let jitter = CGFloat((i * 37) % 7 - 3)
            return (CGPoint(x: stackBase.x + jitter * 0.006 * S, y: stackBase.y - CGFloat(i) * 0.022 * S),
                    C, jitter * 0.012)
        }
    }

    /// Studio: a big sleeve with the record sliding out of it; past sleeves fanned to the right.
    private func buildStudio(transparent: Bool) {
        let S = geo.S, c = CGPoint(x: bounds.midX, y: bounds.midY)
        if !transparent {
            _ = add(gradient(bounds, [hex(0x4E3322), hex(0x140C08)],
                             start: CGPoint(x: 0.4, y: 0.55), end: CGPoint(x: 1.05, y: 1.1), type: .radial), z: -100)
        }

        let C = 0.9 * S
        let sc = CGPoint(x: c.x - 0.25 * S, y: c.y + 0.05 * S)
        let R = 0.43 * S
        geo.R = R
        geo.recordOut = CGPoint(x: sc.x + 0.42 * S, y: sc.y)
        geo.recordIn = CGPoint(x: sc.x + 0.16 * S, y: sc.y)
        makeRecord(center: geo.recordIn, R: R, z: 0)

        let sl = CALayer()
        sl.bounds = CGRect(x: 0, y: 0, width: C, height: C)
        sl.position = sc
        sl.contentsGravity = .resizeAspectFill
        sl.contents = Art.defaultSleeve
        sl.borderWidth = 1
        sl.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        sl.shadowOpacity = 0.65
        sl.shadowRadius = 0.04 * S
        sl.shadowOffset = CGSize(width: 0.01 * S, height: -0.025 * S)
        sleeve = add(sl, z: 10)

        geo.infoRect = CGRect(x: sc.x - C / 2, y: sc.y - C / 2 - 0.24 * S, width: C, height: 0.2 * S)
        geo.infoAlign = .left
        geo.maxStack = 5
        let pileCenter = CGPoint(x: c.x + 0.8 * S, y: c.y - 0.22 * S)
        geo.stackSlot = { i in
            let f = CGFloat(i)
            return (CGPoint(x: pileCenter.x - f * 0.03 * S, y: pileCenter.y + f * 0.012 * S),
                    0.3 * S, -0.08 + f * 0.09)
        }
    }

    /// Midnight: a floating record with a glow tinted by the album, recent covers in a row below.
    private func buildMidnight(transparent: Bool) {
        let S = geo.S, c = CGPoint(x: bounds.midX, y: bounds.midY)
        if !transparent {
            let bg = CALayer()
            bg.frame = bounds
            bg.backgroundColor = hex(0x06070C).cgColor
            _ = add(bg, z: -100)
        }

        let R = 0.42 * S
        let rc = CGPoint(x: c.x, y: c.y + 0.18 * S)
        geo.R = R
        geo.recordOut = rc
        geo.recordIn = rc

        let gr = 1.25 * S
        let g = gradient(CGRect(x: rc.x - gr, y: rc.y - gr, width: 2 * gr, height: 2 * gr), [],
                         start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 1, y: 1), type: .radial)
        g.locations = [0, 0.35, 1]
        glow = add(g, z: -50)

        let ring = CAShapeLayer()
        let rr = R * 1.07
        ring.path = CGPath(ellipseIn: CGRect(x: rc.x - rr, y: rc.y - rr, width: 2 * rr, height: 2 * rr), transform: nil)
        ring.strokeColor = NSColor(white: 1, alpha: 0.12).cgColor
        ring.fillColor = nil
        ring.lineWidth = 1
        _ = add(ring, z: -1)

        makeRecord(center: rc, R: R, z: 0)

        geo.infoRect = CGRect(x: c.x - 0.5 * S, y: c.y - 0.47 * S, width: S, height: 0.2 * S)
        geo.infoAlign = .center
        geo.maxStack = 6
        geo.stackSlot = { i in
            (CGPoint(x: c.x - 0.375 * S + CGFloat(i) * 0.15 * S, y: c.y - 0.56 * S), 0.12 * S, 0)
        }
    }

    private func buildInfo(visible: Bool, shadowed: Bool) {
        let S = geo.S, r = geo.infoRect
        for (t, size, weight, alpha, y) in [
            (titleLayer, 0.042 * S, NSFont.Weight.semibold, 0.95, r.maxY - 0.06 * S),
            (artistLayer, 0.03 * S, NSFont.Weight.regular, 0.65, r.maxY - 0.11 * S),
        ] {
            t.frame = CGRect(x: r.minX, y: y, width: r.width, height: size * 1.35)
            t.font = NSFont.systemFont(ofSize: size, weight: weight)
            t.fontSize = size
            t.foregroundColor = NSColor(white: 1, alpha: alpha).cgColor
            t.alignmentMode = geo.infoAlign
            t.truncationMode = .end
            t.isHidden = !visible
            if shadowed {
                t.shadowOpacity = 0.8
                t.shadowRadius = 3
                t.shadowOffset = .zero
            }
            _ = add(t, z: 30)
        }

        let h = max(2, 0.006 * S)
        barTrack.frame = CGRect(x: r.minX, y: r.maxY - 0.15 * S, width: r.width, height: h)
        barTrack.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        barTrack.cornerRadius = h / 2
        barTrack.isHidden = !visible
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        barFill.bounds = CGRect(x: 0, y: 0, width: 0, height: h)
        barFill.position = CGPoint(x: 0, y: h / 2)
        barFill.backgroundColor = NSColor(white: 1, alpha: 0.85).cgColor
        barFill.cornerRadius = h / 2
        barTrack.addSublayer(barFill)
        _ = add(barTrack, z: 30)
    }

    // MARK: Live state

    @objc private func stateChanged() {
        apply(animated: true)
    }

    private func apply(animated: Bool) {
        let np = NowPlaying.shared, st = Settings.shared
        let playing = np.isPlaying

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.9)

        let art = (st.hideArtWhenPaused && !playing) ? nil : np.artwork
        let artKey = art == nil ? "default" : (np.track?.id ?? "?")
        if artKey != shownArtKey {
            label.contents = art ?? Art.defaultLabel
            sleeve?.contents = art ?? Art.defaultSleeve
            let tint = Art.glowColor(of: art)
            glow?.colors = [tint.withAlphaComponent(0.5), tint.withAlphaComponent(0.14),
                            tint.withAlphaComponent(0)].map(\.cgColor)
            shownArtKey = artKey
        }

        let lowPower = st.pauseInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled
        setSpin(playing && !lowPower)

        arm?.transform = CATransform3DMakeRotation(playing ? -0.4 : 0.06, 0, 0, 1)
        recordGroup.position = playing ? geo.recordOut : geo.recordIn
        lamp?.backgroundColor = (playing ? hex(0xFFB347) : hex(0x3A2A1A)).cgColor
        lamp?.shadowColor = hex(0xFFB347).cgColor
        lamp?.shadowOpacity = playing ? 0.9 : 0

        if let t = np.track {
            titleLayer.string = t.title
            artistLayer.string = [t.artist, t.album].filter { !$0.isEmpty }.joined(separator: " — ")
        } else {
            titleLayer.string = "Nothing playing"
            artistLayer.string = "Play something in Spotify or Apple Music"
        }

        updateStack(animated: animated)
        CATransaction.commit()

        updateProgress()
    }

    private func setSpin(_ on: Bool) {
        if on && spinPaused {
            let paused = rotor.timeOffset
            rotor.speed = 1
            rotor.timeOffset = 0
            rotor.beginTime = 0
            rotor.beginTime = rotor.convertTime(CACurrentMediaTime(), from: nil) - paused
            spinPaused = false
        } else if !on && !spinPaused {
            let now = rotor.convertTime(CACurrentMediaTime(), from: nil)
            rotor.speed = 0
            rotor.timeOffset = now
            spinPaused = true
        }
    }

    /// The bar animates on its own to the end of the track, so no timer is needed.
    private func updateProgress() {
        let np = NowPlaying.shared
        let W = barTrack.bounds.width
        barFill.removeAnimation(forKey: "progress")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guard let t = np.track, t.duration > 0 else {
            barFill.bounds.size.width = 0
            CATransaction.commit()
            return
        }
        let pos = np.currentPosition
        let start = W * CGFloat(pos / t.duration)
        barFill.bounds.size.width = start
        CATransaction.commit()

        if np.isPlaying {
            let a = CABasicAnimation(keyPath: "bounds.size.width")
            a.fromValue = start
            a.toValue = W
            a.duration = max(t.duration - pos, 0.1)
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            barFill.add(a, forKey: "progress")
        }
    }

    /// Lays out recently played covers; a newly added cover flies in from the record.
    private func updateStack(animated: Bool) {
        let items = Array(NowPlaying.shared.recent.prefix(geo.maxStack))
        let ids = Set(items.map(\.id))

        for (id, l) in stackLayers where !ids.contains(id) {
            stackLayers[id] = nil
            CATransaction.begin()
            CATransaction.setCompletionBlock { l.removeFromSuperlayer() }
            l.opacity = 0
            CATransaction.commit()
        }

        for (i, item) in items.enumerated() {
            let (center, size, rot) = geo.stackSlot(i)
            let isNew = stackLayers[item.id] == nil
            let l = stackLayers[item.id] ?? {
                let n = CALayer()
                n.contents = item.image
                n.contentsGravity = .resizeAspectFill
                n.borderWidth = 0.5
                n.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
                n.shadowOpacity = 0.5
                n.shadowRadius = 0.015 * geo.S
                n.shadowOffset = CGSize(width: 0, height: -0.006 * geo.S)
                stackLayers[item.id] = n
                return add(n)
            }()

            l.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            l.position = center
            l.transform = CATransform3DMakeRotation(rot, 0, 0, 1)
            l.zPosition = CGFloat(50 - i)
            l.opacity = 1

            if isNew && animated {
                let from = CABasicAnimation(keyPath: "position")
                from.fromValue = NSValue(point: recordGroup.position)
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                let grow = CABasicAnimation(keyPath: "transform.scale")
                grow.fromValue = 0.5
                let group = CAAnimationGroup()
                group.animations = [from, fade, grow]
                group.duration = 0.9
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                l.add(group, forKey: "enter")
            }
        }
    }
}
