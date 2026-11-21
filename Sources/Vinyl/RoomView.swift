import AppKit
import SceneKit

/// Lamplight, rendered in 3D with SceneKit: a warm room at night with a walnut turntable
/// on a desk, a globe lamp, a framed print lit by a picture light, the current sleeve on a
/// stand and recently played records piled flat. Lighting, soft shadows and bloom do the
/// heavy lifting. Rendering stops entirely while music is paused.
final class RoomView: SCNView {
    var onLayout: ((CGRect) -> Void)?
    private(set) var interactRect = CGRect.zero

    private let room = SCNScene()
    private let cameraNode = SCNNode()
    private let environment = SCNNode()      // wall, desk, lamp, frame: hidden in transparent mode
    private let turntable = SCNNode()
    private let recordSpin = SCNNode()
    private let armPivot = SCNNode()
    private let labelMaterial = SCNMaterial()
    private let sleeveMaterial = SCNMaterial()
    private let frameMaterial = SCNMaterial()
    private let powerLight = SCNMaterial()
    private var stackNodes: [String: SCNNode] = [:]
    private var shownArtKey: String?
    private var frameArtID: String?

    private let recordCenter = SCNVector3(-0.05, 0.106, 0)   // in turntable space

    init(roomFrame frame: NSRect) {
        super.init(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        scene = room
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 30
        rendersContinuously = false
        backgroundColor = .clear
        allowsCameraControl = false

        buildEnvironment()
        buildTurntable()
        buildCamera()

        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged),
                                               name: NowPlaying.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: Settings.didChange, object: nil)
        settingsChanged()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Materials

    private func pbr(_ color: Any, rough: CGFloat, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    private func hex(_ v: UInt32) -> NSColor {
        NSColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private func node(_ g: SCNGeometry, _ pos: SCNVector3, in parent: SCNNode) -> SCNNode {
        let n = SCNNode(geometry: g)
        n.position = pos
        parent.addChildNode(n)
        return n
    }

    // MARK: Room

    private func buildEnvironment() {
        room.rootNode.addChildNode(environment)

        // Wall: warm plaster.
        let wall = SCNPlane(width: 8, height: 4)
        wall.firstMaterial = pbr(hex(0xD99A6C), rough: 0.95)
        node(wall, SCNVector3(0, 2, -0.95), in: environment)

        // Desk: walnut top with a visible front edge.
        let desk = SCNBox(width: 6, height: 0.05, length: 1.5, chamferRadius: 0.004)
        let wood = pbr(Art.woodTexture, rough: 0.5)
        wood.diffuse.wrapS = .repeat
        wood.diffuse.wrapT = .repeat
        wood.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 2, 1)
        desk.materials = [wood]
        node(desk, SCNVector3(0, -0.025, -0.2), in: environment)

        // Globe lamp, back right.
        let lamp = SCNNode()
        lamp.position = SCNVector3(0.72, 0, -0.78)
        environment.addChildNode(lamp)
        let brass = pbr(hex(0xC89B5A), rough: 0.3, metal: 1)
        let foot = SCNCylinder(radius: 0.075, height: 0.018)
        foot.materials = [brass]
        node(foot, SCNVector3(0, 0.009, 0), in: lamp)
        let stem = SCNCylinder(radius: 0.007, height: 0.24)
        stem.materials = [brass]
        node(stem, SCNVector3(0, 0.13, 0), in: lamp)
        let globe = SCNSphere(radius: 0.085)
        let opal = pbr(hex(0x806040), rough: 0.6)
        opal.emission.contents = hex(0xFFB86A)
        opal.emission.intensity = 6
        globe.materials = [opal]
        node(globe, SCNVector3(0, 0.33, 0), in: lamp)
        lamp.enumerateHierarchy { n, _ in n.castsShadow = false }

        // Light from the globe: a soft omni fill plus a shadow-casting spot.
        let glow = SCNLight()
        glow.type = .omni
        glow.color = hex(0xFF9E62)
        glow.intensity = 8
        glow.attenuationStartDistance = 0.1
        glow.attenuationEndDistance = 4
        glow.attenuationFalloffExponent = 1
        node(SCNSphere(radius: 0.001), SCNVector3(0, 0.33, 0), in: lamp).light = glow

        let key = SCNLight()
        key.type = .spot
        key.color = hex(0xFFA872)
        key.intensity = 30
        key.spotInnerAngle = 50
        key.spotOuterAngle = 110
        key.castsShadow = true
        key.shadowRadius = 10
        key.shadowSampleCount = 16
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = NSColor(white: 0, alpha: 0.65)
        key.attenuationStartDistance = 0.2
        key.attenuationEndDistance = 3.5
        key.attenuationFalloffExponent = 1.5
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0.72, 0.45, -0.62)
        keyNode.look(at: SCNVector3(-0.35, 0, -0.25))
        environment.addChildNode(keyNode)

        // Framed print with a brass picture light above it.
        let frame = SCNNode()
        frame.position = SCNVector3(-0.08, 0.47, -0.93)
        environment.addChildNode(frame)
        let darkWood = pbr(hex(0x2A1A10), rough: 0.45)
        let outer = SCNBox(width: 0.34, height: 0.34, length: 0.025, chamferRadius: 0.002)
        outer.materials = [darkWood]
        node(outer, SCNVector3(0, 0, 0), in: frame)
        let mat = SCNPlane(width: 0.3, height: 0.3)
        mat.firstMaterial = pbr(hex(0xEDE3D2), rough: 0.9)
        node(mat, SCNVector3(0, 0, 0.0128), in: frame)
        frameMaterial.lightingModel = .physicallyBased
        frameMaterial.roughness.contents = 0.6
        let print = SCNPlane(width: 0.2, height: 0.2)
        print.materials = [frameMaterial]
        node(print, SCNVector3(0, 0, 0.0132), in: frame)
        let bar = SCNCylinder(radius: 0.008, height: 0.16)
        bar.materials = [brass]
        let barNode = node(bar, SCNVector3(0, 0.215, 0.05), in: frame)
        barNode.eulerAngles.z = .pi / 2
        let pictureLight = SCNLight()
        pictureLight.type = .spot
        pictureLight.color = hex(0xFFC690)
        pictureLight.intensity = 7
        pictureLight.spotInnerAngle = 10
        pictureLight.spotOuterAngle = 95
        let pl = SCNNode()
        pl.light = pictureLight
        pl.position = SCNVector3(0, 0.2, 0.09)
        frame.addChildNode(pl)
        pl.look(at: SCNVector3(-0.08, 0.25, -0.93))

        // Very low warm ambient so shadows stay rich but not black.
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = hex(0x6A4030)
        ambient.intensity = 18
        let a = SCNNode()
        a.light = ambient
        room.rootNode.addChildNode(a)

        // Gentle fill from the viewer's side so front faces aren't lost in shadow.
        let fill = SCNLight()
        fill.type = .directional
        fill.color = hex(0xC8906A)
        fill.intensity = 45
        let f = SCNNode()
        f.light = fill
        f.position = SCNVector3(-0.5, 1, 2)
        f.look(at: SCNVector3(0, 0, -0.3))
        room.rootNode.addChildNode(f)

        // Sleeve on a wooden stand, front left, turned toward the turntable.
        let stand = SCNNode()
        stand.position = SCNVector3(0.43, 0, -0.42)
        stand.eulerAngles.y = -0.3
        room.rootNode.addChildNode(stand)
        let base = SCNBox(width: 0.34, height: 0.022, length: 0.07, chamferRadius: 0.003)
        base.materials = [pbr(Art.woodTexture, rough: 0.45)]
        node(base, SCNVector3(0, 0.011, 0), in: stand)
        sleeveMaterial.lightingModel = .physicallyBased
        sleeveMaterial.roughness.contents = 0.55
        let back = pbr(hex(0xE8E0D0), rough: 0.8)
        let sleeve = SCNBox(width: 0.31, height: 0.31, length: 0.004, chamferRadius: 0.001)
        sleeve.materials = [sleeveMaterial, back, back, back, back, back]
        let s = node(sleeve, SCNVector3(0, 0.172, -0.012), in: stand)
        s.eulerAngles.x = -0.12
    }

    // MARK: Turntable

    private func buildTurntable() {
        turntable.position = SCNVector3(0, 0, -0.3)
        room.rootNode.addChildNode(turntable)

        let oak = pbr(hex(0xB8895A), rough: 0.45)
        let plinth = SCNBox(width: 0.46, height: 0.07, length: 0.34, chamferRadius: 0.008)
        plinth.materials = [oak]
        node(plinth, SCNVector3(0, 0.035, 0), in: turntable)

        let topPlate = SCNBox(width: 0.448, height: 0.008, length: 0.328, chamferRadius: 0.004)
        topPlate.materials = [pbr(hex(0xD9CDB6), rough: 0.6)]
        node(topPlate, SCNVector3(0, 0.074, 0), in: turntable)

        let aluminium = pbr(hex(0xC9C9CC), rough: 0.25, metal: 1)
        let platter = SCNCylinder(radius: 0.152, height: 0.022)
        platter.materials = [aluminium]
        node(platter, SCNVector3(recordCenter.x, 0.089, 0), in: turntable)

        recordSpin.position = SCNVector3(recordCenter.x, 0, 0)
        turntable.addChildNode(recordSpin)
        let vinylSide = pbr(hex(0x0A0A0A), rough: 0.3)
        let vinylTop = pbr(Art.disc(diameter: 1024), rough: 0.28)
        let record = SCNCylinder(radius: 0.149, height: 0.004)
        record.materials = [vinylSide, vinylTop, vinylSide]
        node(record, SCNVector3(0, 0.102, 0), in: recordSpin)
        labelMaterial.lightingModel = .physicallyBased
        labelMaterial.roughness.contents = 0.7
        labelMaterial.diffuse.contents = Art.defaultLabel
        let label = SCNCylinder(radius: 0.05, height: 0.0045)
        label.materials = [vinylSide, labelMaterial, vinylSide]
        node(label, SCNVector3(0, 0.1025, 0), in: recordSpin)
        let spindle = SCNCylinder(radius: 0.003, height: 0.012)
        spindle.materials = [aluminium]
        node(spindle, SCNVector3(0, 0.108, 0), in: recordSpin)
        recordSpin.runAction(.repeatForever(.rotateBy(x: 0, y: -2 * .pi, z: 0, duration: 1.8)))

        // Tonearm: post at the back right; the arm swings in over the record when playing.
        let black = pbr(hex(0x151515), rough: 0.4, metal: 0.6)
        let post = SCNCylinder(radius: 0.016, height: 0.05)
        post.materials = [black]
        node(post, SCNVector3(0.165, 0.103, -0.11), in: turntable)
        armPivot.position = SCNVector3(0.165, 0.13, -0.11)
        turntable.addChildNode(armPivot)
        let chrome = pbr(hex(0xE0E0E2), rough: 0.15, metal: 1)
        let tube = SCNCylinder(radius: 0.0042, height: 0.25)
        tube.materials = [chrome]
        let t = node(tube, SCNVector3(0, 0, 0.125), in: armPivot)
        t.eulerAngles.x = .pi / 2
        let head = SCNBox(width: 0.02, height: 0.008, length: 0.034, chamferRadius: 0.002)
        head.materials = [black]
        node(head, SCNVector3(0, -0.006, 0.255), in: armPivot)
        let weight = SCNCylinder(radius: 0.014, height: 0.03)
        weight.materials = [black]
        let w = node(weight, SCNVector3(0, 0, -0.045), in: armPivot)
        w.eulerAngles.x = .pi / 2
        let rest = SCNCylinder(radius: 0.004, height: 0.03)
        rest.materials = [black]
        node(rest, SCNVector3(0.165, 0.093, 0.14), in: turntable)

        // Power light and a brass speed knob on the front right of the top plate.
        powerLight.lightingModel = .physicallyBased
        powerLight.diffuse.contents = hex(0x301A0A)
        let led = SCNCylinder(radius: 0.005, height: 0.002)
        led.materials = [powerLight]
        node(led, SCNVector3(0.12, 0.079, 0.13), in: turntable)
        let knob = SCNCylinder(radius: 0.012, height: 0.012)
        knob.materials = [pbr(hex(0xC89B5A), rough: 0.3, metal: 1)]
        node(knob, SCNVector3(0.175, 0.084, 0.13), in: turntable)
    }

    private func buildCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 40
        cam.zNear = 0.05
        cam.zFar = 20
        cam.wantsHDR = true
        cam.bloomIntensity = 0.8
        cam.bloomThreshold = 0.75
        cam.bloomBlurRadius = 9
        cam.vignettingIntensity = 0.7
        cam.vignettingPower = 0.8
        cam.screenSpaceAmbientOcclusionIntensity = 1.2
        cam.screenSpaceAmbientOcclusionRadius = 0.06
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = -0.3
        cam.saturation = 0.92
        cameraNode.camera = cam
        room.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
    }

    private func placeCamera() {
        let distance: Float
        switch Settings.shared.transparent ? .mid : Settings.shared.framing {
        case .wide: distance = 1.15
        case .mid: distance = 0.88
        case .close: distance = 0.7
        }
        cameraNode.position = SCNVector3(0, 0.1 + 0.3 * CGFloat(distance), CGFloat(distance))
        cameraNode.look(at: SCNVector3(0, 0.12, -0.4))
    }

    // MARK: Live state

    @objc private func settingsChanged() {
        let transparent = Settings.shared.transparent
        environment.isHidden = transparent
        room.background.contents = transparent ? NSColor.clear : hex(0x140A06)
        placeCamera()
        shownArtKey = nil
        stateChanged()
        updateInteractRect()
    }

    @objc private func stateChanged() {
        let np = NowPlaying.shared, st = Settings.shared
        let playing = np.isPlaying
        let lowPower = st.pauseInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled

        let art = (st.hideArtWhenPaused && !playing) ? nil : np.artwork
        let key = art == nil ? "default" : (np.track?.id ?? "?")
        if key != shownArtKey {
            labelMaterial.diffuse.contents = art ?? Art.defaultLabel
            sleeveMaterial.diffuse.contents = art ?? Art.defaultSleeve
            shownArtKey = key
        }
        let last = np.recent.first
        if last?.id != frameArtID || frameMaterial.diffuse.contents == nil {
            frameMaterial.diffuse.contents = last?.image ?? Art.defaultSleeve
            frameArtID = last?.id
        }

        recordSpin.isPaused = scratching || !(playing && !lowPower)
        armPivot.removeAllActions()
        let action = SCNAction.rotateTo(x: 0, y: playing ? -0.55 : 0.05, z: 0, duration: 1.0, usesShortestUnitArc: true)
        action.timingMode = .easeInEaseOut
        armPivot.runAction(action)
        powerLight.emission.contents = playing ? hex(0xFF9A40) : NSColor.black
        powerLight.emission.intensity = playing ? 3 : 0

        updateStack()

        // Render continuously only while something moves; one frame otherwise.
        isPlaying = playing && !lowPower
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.2
        SCNTransaction.completionBlock = { [weak self] in self?.needsDisplay = true }
        SCNTransaction.commit()
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.needsDisplay = true }
    }

    private func updateStack() {
        let items = Array(NowPlaying.shared.recent.prefix(6))
        let ids = Set(items.map(\.id))
        for (id, n) in stackNodes where !ids.contains(id) {
            stackNodes[id] = nil
            n.runAction(.sequence([.fadeOut(duration: 0.4), .removeFromParentNode()]))
        }
        let pile = SCNVector3(-0.5, 0, -0.2)
        let count = items.count
        for (i, item) in items.enumerated() {
            let level = CGFloat(count - 1 - i)               // newest on top
            let jitter = CGFloat((i * 53) % 9 - 4)
            let target = SCNVector3(pile.x + jitter * 0.006, 0.0025 + level * 0.0032, pile.z + jitter * 0.004)
            let angle = jitter * 0.05 + 0.2
            if let n = stackNodes[item.id] {
                n.runAction(.group([.move(to: target, duration: 0.6), .rotateTo(x: 0, y: angle, z: 0, duration: 0.6)]))
                continue
            }
            let face = SCNMaterial()
            face.lightingModel = .physicallyBased
            face.diffuse.contents = item.image
            face.roughness.contents = 0.55
            let paper = pbr(hex(0x6E5A48), rough: 0.8)
            let cover = SCNBox(width: 0.31, height: 0.003, length: 0.31, chamferRadius: 0.0008)
            cover.materials = [paper, paper, paper, paper, face, paper]
            let n = SCNNode(geometry: cover)
            let from = turntable.convertPosition(SCNVector3(recordCenter.x, 0.2, 0), to: nil)
            n.position = shownArtKey == nil ? target : from
            n.eulerAngles.y = angle
            n.opacity = 0
            room.rootNode.addChildNode(n)
            stackNodes[item.id] = n
            n.runAction(.group([.fadeIn(duration: 0.5),
                                .move(to: target, duration: 0.9)]))
        }
    }

    // MARK: Scratching

    private var scratching = false

    func beginScratch() {
        scratching = true
        recordSpin.isPaused = true
        rendersContinuously = true
    }

    /// Turns the record by `angle` radians; positive is the normal playing direction.
    func scratch(by angle: CGFloat) {
        recordSpin.eulerAngles.y -= angle
    }

    func endScratch() {
        scratching = false
        rendersContinuously = false
        stateChanged()
    }

    // MARK: Hit area for the controls panel

    override func layout() {
        super.layout()
        updateInteractRect()
    }

    private func updateInteractRect() {
        guard bounds.width > 0 else { return }
        let (minB, maxB) = turntable.boundingBox
        var rect = CGRect.null
        for x in [minB.x, maxB.x] {
            for y in [minB.y, maxB.y + 0.03] {
                for z in [minB.z, maxB.z] {
                    let world = turntable.convertPosition(SCNVector3(x, y, z), to: nil)
                    let p = projectPoint(world)
                    rect = rect.union(CGRect(x: p.x, y: p.y, width: 0, height: 0))
                }
            }
        }
        guard !rect.isNull, rect != interactRect else { return }
        interactRect = rect
        onLayout?(rect)
    }
}
