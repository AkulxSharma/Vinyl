# Vinyl (open source)

An open-source take on the "Vinyl for Mac" idea: your desktop wallpaper becomes a live record player. While Spotify or Apple Music plays, a record spins on your desktop with the album art on its label. Each time the song changes, the last record joins a stack of recently played covers. It's free, written from scratch in Swift, and not affiliated with the commercial Vinyl for Mac app.

## Features

- **Four scenes**, switchable from the menu bar:
  - **Lamplight** (default): a warm room at night. A desk globe of the Earth turns slowly while music plays, and you can drag it to spin it. A framed print under a picture light shows your previous album. The turntable sits at an angle on a walnut desk, the current sleeve leans on a stand, and played records pile up flat beside it.
  - **Deck:** a turntable on a wooden table. The tonearm swings onto the record when music plays, and played records pile up beside it.
  - **Studio:** a large album sleeve. The record slides out when you press play and back in when you pause, and past covers fan out to the side.
  - **Midnight:** a floating record on a dark background, with a glow tinted by the album's colors and recent covers in a row underneath.
- **Framing:** Wide, Mid or Close.
- **Transparent mode:** drops the scene background so the player sits on your own wallpaper. Choose Small, Medium or Large.
- **Clickable:** hover over the player for previous / play-pause / next buttons, or click the record to play or pause. Only the player area takes clicks; the rest of the desktop works as usual.
- **Live info:** track name, artist, album and a progress bar.
- **Playback aware:** the record stops spinning when you pause. Artwork can optionally hide while paused.
- **Light on resources:** spinning and the progress bar run as Core Animation animations, so no timers redraw the screen. In Low Power Mode the record stops spinning.
- **Spotify and Apple Music**, with no login, account or API key. Works on every display and every Space, and launch at login is optional.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+ (Xcode or the Command Line Tools)

## Build and run

```bash
git clone https://github.com/AkulxSharma/Vinyl.git
cd Vinyl
./build.sh --install   # builds Vinyl.app, copies it to ~/Applications and opens it
```

Vinyl lives in the menu bar (the record icon), not the Dock. Use that menu for scenes and settings, or to quit.

## How it works

- **Window:** a borderless window per display sits at the desktop window level, above the wallpaper and below your desktop icons. A small panel just above the icon layer covers only the player and handles clicks.
- **Track and play state:** both players broadcast these as distributed notifications (`com.spotify.client.PlaybackStateChanged` and `com.apple.Music.playerInfo`), so Vinyl needs no permission for them.
- **AppleScript:** used only to read the state at launch, Music's playback position and album artwork. The first time, macOS asks whether Vinyl may control Spotify or Music. If you decline, artwork falls back to Spotify's public oEmbed endpoint and the iTunes Search API.
- **Recent covers:** cached in `~/Library/Caches/dev.akulsharma.vinyl`.

Because `build.sh` signs the app ad hoc, macOS may ask for Automation access again after each rebuild.

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

## Credits

The Earth texture is `earth_atmos_2048.jpg` from the three.js examples (MIT), which is derived from NASA's Blue Marble imagery (public domain).

## License

MIT
