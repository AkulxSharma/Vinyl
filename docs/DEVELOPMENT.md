# Development

## Build from source

```bash
./build.sh            # builds build/Vinyl.app
./build.sh --install  # also copies it to ~/Applications and opens it
```

Requires macOS 14 or later and Swift 5.10+ (Xcode or the Command Line Tools). `build.sh` signs the app ad hoc, so macOS may ask for Automation access again after each rebuild.

## How it works

- **Window:** a borderless window per display sits at the desktop window level, above the wallpaper and below your desktop icons. A small panel just above the icon layer covers only the player and handles clicks.
- **Track and play state:** both players broadcast these as distributed notifications (`com.spotify.client.PlaybackStateChanged` and `com.apple.Music.playerInfo`), so Vinyl needs no permission for them.
- **AppleScript:** used only to read the state at launch, Music's playback position and album artwork. The first time, macOS asks whether Vinyl may control Spotify or Music. If you decline, artwork falls back to Spotify's public oEmbed endpoint and the iTunes Search API.
- **Recent covers:** cached in `~/Library/Caches/dev.akulsharma.vinyl`.

## Project layout

| File | Purpose |
| --- | --- |
| `Sources/Vinyl/main.swift` | App delegate; creates one desktop window per screen |
| `Sources/Vinyl/DesktopWindow.swift` | The desktop-level, click-through window |
| `Sources/Vinyl/SceneView.swift` | The scenes, spin, tonearm, stack and progress |
| `Sources/Vinyl/Room.swift` | Painted backdrop for the Lamplight room |
| `Sources/Vinyl/Controls.swift` | Click and hover controls over the player |
| `Sources/Vinyl/NowPlaying.swift` | Spotify and Apple Music state, artwork, recent covers |
| `Sources/Vinyl/Art.swift` | Procedurally drawn record, default label and sleeve |
| `Sources/Vinyl/StatusMenu.swift` | Menu bar menu |
| `Sources/Vinyl/Settings.swift` | Preferences |
