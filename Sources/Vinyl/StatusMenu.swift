import AppKit
import ServiceManagement

/// A menu item that runs a closure, so the menu can be built declaratively.
private final class ClosureItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, enabled: Bool = true, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

/// The menu bar icon. The menu is rebuilt each time it opens so it always shows
/// the current track and settings.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Vinyl")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let np = NowPlaying.shared, st = Settings.shared

        let header = NSMenuItem(title: np.track.map { "\($0.title) — \($0.artist)" } ?? "Nothing playing",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(submenu("Scene", SceneKind.allCases.map { s in
            ClosureItem(s.title, checked: st.scene == s) { st.scene = s }
        }))
        let framing = submenu("Framing", Framing.allCases.map { f in
            ClosureItem(f.title, checked: st.framing == f) { st.framing = f }
        })
        framing.isEnabled = !st.transparent
        menu.addItem(framing)

        menu.addItem(ClosureItem("Transparent Background", checked: st.transparent) { st.transparent.toggle() })
        let size = submenu("Player Size", OverlaySize.allCases.map { o in
            ClosureItem(o.title, checked: st.overlaySize == o) { st.overlaySize = o }
        })
        size.isEnabled = st.transparent
        menu.addItem(size)
        menu.addItem(.separator())

        menu.addItem(ClosureItem("Show Track Info", checked: st.showInfo) { st.showInfo.toggle() })
        menu.addItem(ClosureItem("Hide Artwork While Paused", checked: st.hideArtWhenPaused) {
            st.hideArtWhenPaused.toggle()
        })
        menu.addItem(ClosureItem("Stop Spinning in Low Power Mode", checked: st.pauseInLowPower) {
            st.pauseInLowPower.toggle()
        })
        menu.addItem(ClosureItem("Clear Record Stack", enabled: !np.recent.isEmpty) { np.clearRecent() })
        menu.addItem(.separator())

        if np.automationDenied {
            menu.addItem(ClosureItem("Allow Album Art Access…") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            })
        }
        let login = SMAppService.mainApp
        menu.addItem(ClosureItem("Launch at Login", checked: login.status == .enabled) {
            do {
                if login.status == .enabled { try login.unregister() } else { try login.register() }
            } catch {
                NSLog("Vinyl: launch at login failed: \(error)")
            }
        })
        menu.addItem(ClosureItem("Quit Vinyl") { NSApp.terminate(nil) })
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        sub.autoenablesItems = false
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }
}
