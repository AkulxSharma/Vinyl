import AppKit

struct TrackInfo: Equatable {
    var id: String
    var title: String
    var artist: String
    var album: String
    /// Seconds.
    var duration: Double
}

enum PlayerSource: String {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }
}

/// Tracks what Spotify or Apple Music is playing.
///
/// Track and play-state changes arrive through the distributed notifications both
/// players broadcast, which need no permission. AppleScript is used only to read the
/// initial state at launch, the playback position for Music, and album artwork; that
/// triggers macOS's one-time Automation prompt. If the prompt is declined, artwork
/// falls back to public lookups (Spotify oEmbed, iTunes Search).
final class NowPlaying {
    static let shared = NowPlaying()
    static let didChange = Notification.Name("VinylNowPlayingChanged")

    private(set) var source: PlayerSource?
    private(set) var track: TrackInfo?
    private(set) var artwork: CGImage?
    private(set) var isPlaying = false
    /// Covers of previously played tracks, newest first.
    private(set) var recent: [(id: String, image: CGImage)] = []
    /// Set when macOS denied Automation access to a player.
    private(set) var automationDenied = false

    private var position: Double = 0
    private var positionStamp = Date()
    private var artCache: [String: CGImage] = [:]
    private let scriptQueue = DispatchQueue(label: "vinyl.applescript")
    private var resyncTimer: Timer?
    private let maxRecent = 8

    /// Playback position in seconds, extrapolated from the last report.
    var currentPosition: Double {
        guard let t = track else { return 0 }
        let p = position + (isPlaying ? Date().timeIntervalSince(positionStamp) : 0)
        return min(max(p, 0), max(t.duration, 0))
    }

    // MARK: Lifecycle

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"),
                        object: nil, queue: .main) { [weak self] n in
            self?.handleSpotify(n.userInfo ?? [:])
        }
        dnc.addObserver(forName: .init("com.apple.Music.playerInfo"),
                        object: nil, queue: .main) { [weak self] n in
            self?.handleMusic(n.userInfo ?? [:])
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self, app?.bundleIdentifier == self.source?.rawValue else { return }
            self.setPlaying(false)
        }
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.post()
        }

        loadRecent()
        pollInitialState()

        // Music doesn't announce seeks, so re-read the position now and then while playing.
        resyncTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.resyncPosition()
        }
    }

    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    /// Sends a transport command to the active player (or whichever one is open).
    /// Play/pause flips the UI right away; the player's notification then confirms it.
    func send(_ command: Command) {
        let target = source ?? (PlayerSource.spotify.isRunning ? .spotify : .music)
        guard target.isRunning else {
            NSWorkspace.shared.open(URL(fileURLWithPath: target == .spotify
                ? "/Applications/Spotify.app" : "/System/Applications/Music.app"))
            return
        }
        if command == .playPause, track != nil {
            source = target
            setPlaying(!isPlaying)
        }
        scriptQueue.async { _ = self.run(target, command.rawValue) }
    }

    func clearRecent() {
        recent.removeAll()
        saveRecent()
        post()
    }

    // MARK: Player notifications

    private func handleSpotify(_ info: [AnyHashable: Any]) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        let playing = state == "playing"
        if source != .spotify && !playing { return }
        guard let id = info["Track ID"] as? String, !id.isEmpty else {
            if source == .spotify { setPlaying(false) }
            return
        }
        let t = TrackInfo(
            id: id,
            title: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000)
        let pos = (info["Playback Position"] as? NSNumber)?.doubleValue
        apply(source: .spotify, track: t, playing: playing, position: pos)
    }

    private func handleMusic(_ info: [AnyHashable: Any]) {
        let state = (info["Player State"] as? String ?? "").lowercased()
        let playing = state == "playing"
        if source != .music && !playing { return }
        guard let name = info["Name"] as? String, !name.isEmpty else {
            if source == .music { setPlaying(false) }
            return
        }
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let t = TrackInfo(
            id: Self.musicID(name, artist, album),
            title: name, artist: artist, album: album,
            duration: ((info["Total Time"] as? NSNumber)?.doubleValue ?? 0) / 1000)
        apply(source: .music, track: t, playing: playing, position: nil)
        resyncPosition()
    }

    private static func musicID(_ name: String, _ artist: String, _ album: String) -> String {
        "music:\(name)|\(artist)|\(album)"
    }

    // MARK: State

    private func apply(source s: PlayerSource, track t: TrackInfo, playing: Bool, position p: Double?) {
        let before = currentPosition
        let trackChanged = t.id != track?.id

        if trackChanged, let old = track, let art = artwork {
            pushRecent(id: old.id, image: art)
        }

        source = s
        isPlaying = playing
        track = t

        if let p {
            position = p
        } else if trackChanged {
            position = 0
        } else {
            position = before
        }
        positionStamp = Date()

        if trackChanged {
            artwork = artCache[t.id]
            if artwork == nil { fetchArtwork(for: t, from: s) }
        }
        post()
    }

    private func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        position = currentPosition
        positionStamp = Date()
        isPlaying = playing
        post()
    }

    private func post() {
        NotificationCenter.default.post(name: NowPlaying.didChange, object: nil)
    }

    // MARK: AppleScript

    /// Runs a script against a player, but only if that player is already open,
    /// so querying never relaunches an app the user quit.
    private func run(_ source: PlayerSource, _ body: String) -> NSAppleEventDescriptor? {
        guard source.isRunning else { return nil }
        let script = "tell application id \"\(source.rawValue)\"\n\(body)\nend tell"
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error, let code = error[NSAppleScript.errorNumber] as? Int, code == -1743 {
            DispatchQueue.main.async { self.automationDenied = true }
        }
        return error == nil ? result : nil
    }

    private func queryState(_ s: PlayerSource) -> (playing: Bool, track: TrackInfo, position: Double)? {
        let body = """
        set s to player state as string
        set t to current track
        return {s, name of t, artist of t, album of t, duration of t, player position, id of t}
        """
        guard let d = run(s, body), d.numberOfItems >= 7 else { return nil }
        let state = d.atIndex(1)?.stringValue ?? ""
        let name = d.atIndex(2)?.stringValue ?? ""
        let artist = d.atIndex(3)?.stringValue ?? ""
        let album = d.atIndex(4)?.stringValue ?? ""
        let rawDuration = d.atIndex(5)?.doubleValue ?? 0
        let pos = d.atIndex(6)?.doubleValue ?? 0
        guard !name.isEmpty else { return nil }

        let t: TrackInfo
        switch s {
        case .spotify:
            t = TrackInfo(id: d.atIndex(7)?.stringValue ?? name, title: name, artist: artist,
                          album: album, duration: rawDuration / 1000)
        case .music:
            t = TrackInfo(id: Self.musicID(name, artist, album), title: name, artist: artist,
                          album: album, duration: rawDuration)
        }
        return (state == "playing", t, pos)
    }

    private func pollInitialState() {
        scriptQueue.async {
            let found = [PlayerSource.spotify, .music].compactMap { s in
                self.queryState(s).map { (s, $0) }
            }
            DispatchQueue.main.async {
                guard self.track == nil,
                      let pick = found.first(where: { $0.1.playing }) ?? found.first else { return }
                self.apply(source: pick.0, track: pick.1.track, playing: pick.1.playing,
                           position: pick.1.position)
            }
        }
    }

    private func resyncPosition() {
        guard isPlaying, let s = source, let id = track?.id else { return }
        scriptQueue.async {
            guard let pos = self.run(s, "return player position")?.doubleValue else { return }
            DispatchQueue.main.async {
                guard self.track?.id == id else { return }
                let drift = abs(self.currentPosition - pos)
                self.position = pos
                self.positionStamp = Date()
                if drift > 1.5 { self.post() }
            }
        }
    }

    // MARK: Artwork

    private func fetchArtwork(for t: TrackInfo, from s: PlayerSource) {
        scriptQueue.async {
            var image: CGImage?
            switch s {
            case .spotify:
                var url = self.run(s, "return artwork url of current track")?.stringValue
                if (url ?? "").isEmpty { url = Self.spotifyOEmbedThumbnail(trackID: t.id) }
                if let url, let u = URL(string: url) { image = Self.download(u) }
            case .music:
                let body = """
                if (count of artworks of current track) > 0 then
                    return raw data of artwork 1 of current track
                end if
                """
                if let data = self.run(s, body)?.data, !data.isEmpty {
                    image = Self.cgImage(from: data)
                }
                if image == nil, let u = Self.iTunesArtworkURL(artist: t.artist, album: t.album) {
                    image = Self.download(u)
                }
            }
            DispatchQueue.main.async {
                guard let image else { return }
                self.artCache[t.id] = image
                if self.track?.id == t.id {
                    self.artwork = image
                    self.post()
                }
            }
        }
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func download(_ url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return cgImage(from: data)
    }

    private static func fetchJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Spotify's public oEmbed endpoint returns cover art without any login.
    private static func spotifyOEmbedThumbnail(trackID: String) -> String? {
        guard trackID.hasPrefix("spotify:track:") else { return nil }
        let id = trackID.replacingOccurrences(of: "spotify:track:", with: "")
        var c = URLComponents(string: "https://open.spotify.com/oembed")!
        c.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/track/\(id)")]
        guard let url = c.url else { return nil }
        return fetchJSON(url)?["thumbnail_url"] as? String
    }

    /// Fallback cover lookup for Apple Music tracks via the public iTunes Search API.
    private static func iTunesArtworkURL(artist: String, album: String) -> URL? {
        let term = "\(artist) \(album)".trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return nil }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: term),
                        URLQueryItem(name: "entity", value: "album"),
                        URLQueryItem(name: "limit", value: "1")]
        guard let url = c.url,
              let results = fetchJSON(url)?["results"] as? [[String: Any]],
              let small = results.first?["artworkUrl100"] as? String else { return nil }
        return URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
    }

    // MARK: Recently played stack (persisted in ~/Library/Caches)

    private func pushRecent(id: String, image: CGImage) {
        recent.removeAll { $0.id == id }
        recent.insert((id, image), at: 0)
        if recent.count > maxRecent { recent.removeLast(recent.count - maxRecent) }
        saveRecent()
    }

    private var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("dev.akulsharma.vinyl/recent", isDirectory: true)
    }

    private static func fileName(for id: String) -> String {
        // FNV-1a: stable across launches, unlike Swift's randomized hashValue.
        var h: UInt64 = 0xcbf29ce484222325
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16) + ".jpg"
    }

    private func saveRecent() {
        let items = recent
        let dir = cacheDir
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for item in items {
                let url = dir.appendingPathComponent(Self.fileName(for: item.id))
                if FileManager.default.fileExists(atPath: url.path) { continue }
                let rep = NSBitmapImageRep(cgImage: item.image)
                try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.write(to: url)
            }
        }
        UserDefaults.standard.set(items.map(\.id), forKey: "recentIDs")
    }

    private func loadRecent() {
        let ids = UserDefaults.standard.stringArray(forKey: "recentIDs") ?? []
        recent = ids.compactMap { id in
            let url = cacheDir.appendingPathComponent(Self.fileName(for: id))
            guard let data = try? Data(contentsOf: url), let img = Self.cgImage(from: data) else { return nil }
            return (id, img)
        }
    }
}
