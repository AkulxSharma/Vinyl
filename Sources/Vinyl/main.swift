import AppKit

/// Entry point. Vinyl runs as a menu bar accessory (no Dock icon) and draws
/// one borderless window per display at desktop level, beneath the icons.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var desktops: [DesktopWindowController] = []
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NowPlaying.shared.start()
        rebuildDesktops()
        statusMenu = StatusMenu()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screensChanged() {
        rebuildDesktops()
    }

    private func rebuildDesktops() {
        desktops.forEach { $0.close() }
        desktops = NSScreen.screens.map { DesktopWindowController(screen: $0) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
