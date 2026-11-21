import AppKit

/// Hosts whichever renderer the chosen scene needs: the 3D `RoomView` for Lamplight,
/// the Core Animation `SceneView` for the others. Swaps when the scene setting changes.
final class SceneHost: NSView {
    var onLayout: ((CGRect) -> Void)?
    var onGlobeLayout: ((CGRect) -> Void)?
    var globeRect: CGRect { (current as? RoomView)?.globeRect ?? .zero }
    var room: RoomView? { current as? RoomView }
    private let scale: CGFloat
    private var current: NSView?
    private var showingRoom = false

    var interactRect: CGRect {
        (current as? RoomView)?.interactRect ?? (current as? SceneView)?.interactRect ?? .zero
    }

    init(frame: NSRect, backingScale: CGFloat) {
        scale = backingScale
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(sync),
                                               name: Settings.didChange, object: nil)
        sync()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    func beginScratch() {
        (current as? RoomView)?.beginScratch()
        (current as? SceneView)?.beginScratch()
    }

    func scratch(by angle: CGFloat) {
        (current as? RoomView)?.scratch(by: angle)
        (current as? SceneView)?.scratch(by: angle)
    }

    func endScratch() {
        (current as? RoomView)?.endScratch()
        (current as? SceneView)?.endScratch()
    }

    @objc private func sync() {
        let wantRoom = Settings.shared.scene == .lamplight
        if current != nil && wantRoom == showingRoom { return }
        current?.removeFromSuperview()
        showingRoom = wantRoom
        let forward: (CGRect) -> Void = { [weak self] r in self?.onLayout?(r) }
        if wantRoom {
            let v = RoomView(roomFrame: bounds)
            v.onLayout = forward
            v.onGlobeLayout = { [weak self] r in self?.onGlobeLayout?(r) }
            current = v
        } else {
            let v = SceneView(frame: bounds, backingScale: scale)
            v.onLayout = forward
            current = v
        }
        current!.autoresizingMask = [.width, .height]
        addSubview(current!)
        onLayout?(interactRect)
        onGlobeLayout?(globeRect)
    }
}
