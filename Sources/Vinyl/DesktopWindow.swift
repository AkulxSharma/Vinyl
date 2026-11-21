import AppKit

/// A borderless, click-through window pinned to the desktop layer of one screen.
/// It sits above the wallpaper and below Finder's desktop icons, on every Space.
final class DesktopWindowController {
    private let window: NSWindow
    private let controls = ControlsPanel()

    init(screen: NSScreen) {
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let view = SceneView(frame: NSRect(origin: .zero, size: screen.frame.size),
                             backingScale: screen.backingScaleFactor)
        view.onLayout = { [weak self] rect in self?.controls.place(rect, on: screen) }
        window.contentView = view
        window.orderFront(nil)
        controls.place(view.interactRect, on: screen)
    }

    func close() {
        controls.orderOut(nil)
        controls.close()
        window.orderOut(nil)
        window.close()
    }
}
