import Foundation

enum SceneKind: String, CaseIterable {
    case deck, studio, midnight

    var title: String {
        switch self {
        case .deck: return "Deck"
        case .studio: return "Studio"
        case .midnight: return "Midnight"
        }
    }
}

/// How much of the screen the scene fills when it draws its own background.
enum Framing: String, CaseIterable {
    case wide, mid, close

    var title: String { rawValue.capitalized }

    var factor: CGFloat {
        switch self {
        case .wide: return 0.46
        case .mid: return 0.62
        case .close: return 0.78
        }
    }
}

/// Size of the player when transparent mode puts it on top of your own wallpaper.
enum OverlaySize: String, CaseIterable {
    case small, medium, large

    var title: String { rawValue.capitalized }

    var factor: CGFloat {
        switch self {
        case .small: return 0.30
        case .medium: return 0.42
        case .large: return 0.56
        }
    }
}

/// User preferences, persisted in UserDefaults. Any change posts `didChange`,
/// which makes every desktop scene rebuild itself.
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("VinylSettingsChanged")

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "scene": SceneKind.deck.rawValue,
            "framing": Framing.mid.rawValue,
            "overlaySize": OverlaySize.medium.rawValue,
            "transparent": false,
            "showInfo": true,
            "hideArtWhenPaused": false,
            "pauseInLowPower": true,
        ])
    }

    private func changed() {
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    var scene: SceneKind {
        get { SceneKind(rawValue: defaults.string(forKey: "scene") ?? "") ?? .deck }
        set { defaults.set(newValue.rawValue, forKey: "scene"); changed() }
    }

    var framing: Framing {
        get { Framing(rawValue: defaults.string(forKey: "framing") ?? "") ?? .mid }
        set { defaults.set(newValue.rawValue, forKey: "framing"); changed() }
    }

    var overlaySize: OverlaySize {
        get { OverlaySize(rawValue: defaults.string(forKey: "overlaySize") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "overlaySize"); changed() }
    }

    var transparent: Bool {
        get { defaults.bool(forKey: "transparent") }
        set { defaults.set(newValue, forKey: "transparent"); changed() }
    }

    var showInfo: Bool {
        get { defaults.bool(forKey: "showInfo") }
        set { defaults.set(newValue, forKey: "showInfo"); changed() }
    }

    var hideArtWhenPaused: Bool {
        get { defaults.bool(forKey: "hideArtWhenPaused") }
        set { defaults.set(newValue, forKey: "hideArtWhenPaused"); changed() }
    }

    var pauseInLowPower: Bool {
        get { defaults.bool(forKey: "pauseInLowPower") }
        set { defaults.set(newValue, forKey: "pauseInLowPower"); changed() }
    }
}
