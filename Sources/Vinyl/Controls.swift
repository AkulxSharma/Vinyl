import AppKit

/// A small transparent panel laid over the player that makes it clickable.
///
/// The scene itself lives below Finder's desktop icons, where it can't receive clicks.
/// This panel sits just above the icon layer (still below every normal window) and only
/// covers the player, so the rest of the desktop behaves as usual. Hovering shows
/// previous / play-pause / next buttons; clicking the record toggles playback.
final class ControlsPanel: NSPanel {
    private let controls = ControlsView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isOpaque = false
        // Fully clear pixels would let clicks fall through to the desktop, so keep a
        // practically invisible tint.
        backgroundColor = NSColor(white: 0, alpha: 0.01)
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        contentView = controls
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `rect` is the player area in the screen's local coordinates.
    func place(_ rect: CGRect, on screen: NSScreen) {
        guard rect.width > 0 else { orderOut(nil); return }
        let pill = ControlsView.pillHeight + 12
        let frame = CGRect(x: screen.frame.minX + rect.minX, y: screen.frame.minY + rect.minY,
                           width: rect.width, height: rect.height + pill)
        setFrame(frame, display: true)
        controls.playerHeight = rect.height
        orderFront(nil)
    }
}

private final class ControlsView: NSView {
    static let pillHeight: CGFloat = 40
    var playerHeight: CGFloat = 0 { didSet { needsLayout = true } }

    private let pill = NSVisualEffectView()
    private let playButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        pill.material = .hudWindow
        pill.blendingMode = .behindWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = Self.pillHeight / 2
        pill.alphaValue = 0
        addSubview(pill)

        let stack = NSStackView(views: [
            button("backward.fill", #selector(previous)),
            playButton,
            button("forward.fill", #selector(next)),
        ])
        configure(playButton, "playpause.fill", #selector(togglePlay))
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NowPlaying.didChange, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func button(_ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton()
        configure(b, symbol, action)
        return b
    }

    private func configure(_ b: NSButton, _ symbol: String, _ action: Selector) {
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        b.isBordered = false
        b.contentTintColor = .white
        b.target = self
        b.action = action
    }

    @objc private func refresh() {
        let symbol = NowPlaying.shared.isPlaying ? "pause.fill" : "play.fill"
        playButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))
    }

    override func layout() {
        super.layout()
        let w: CGFloat = 150
        pill.frame = CGRect(x: (bounds.width - w) / 2, y: playerHeight + 6, width: w, height: Self.pillHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setPill(visible: true) }
    override func mouseExited(with event: NSEvent) { setPill(visible: false) }

    private func setPill(visible: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            pill.animator().alphaValue = visible ? 1 : 0
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.y <= playerHeight { togglePlay() }
    }

    @objc private func togglePlay() { NowPlaying.shared.send(.playPause) }
    @objc private func next() { NowPlaying.shared.send(.next) }
    @objc private func previous() { NowPlaying.shared.send(.previous) }
}
