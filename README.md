# ezclip

**Context-aware screenshot curation for designers.**

Double-tap ⌘⌘ on any Mac window and ezclip captures a screenshot with rich context — website URLs, song names, Figma file names, and more. Save inspiration without losing the source.

## Features

- **⌘⌘ hotkey** — double-tap Command to capture the frontmost window
- **Context-aware** — auto-extracts URLs, page titles, song/artist names, Figma file names
- **Scrolling screenshots** — full-page capture for Safari and Chrome
- **Auto-tagging** — domain names, app names, artists become tags automatically
- **Local library** — browse, search, filter by context type, add notes
- **Menu bar + Dock** — always accessible, never in the way
- **No cloud** — everything stored locally in `~/Library/Application Support/ezclip/`

## How it works

| Capture from | What it saves |
|---|---|
| Safari / Chrome / Arc | URL, page title, favicon |
| Spotify / Apple Music | Song, artist, album, album art |
| Figma | File name, page name |
| Finder | Current folder path |
| Anything else | App name, window title, timestamp |

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon (M1/M2/M3/M4)

## Install

### Download DMG

Download the latest DMG from [Releases](https://github.com/namaankohli/ezclip/releases), open it, and drag ezclip to Applications.

### Build from source

```bash
git clone https://github.com/namaankohli/ezclip.git
cd ezclip
./Scripts/build.sh
open build/
```

## Permissions

On first launch, grant two permissions:
1. **Screen Recording** — to capture window screenshots
2. **Accessibility** — to read window titles and detect the ⌘⌘ hotkey

Manage them anytime in System Settings → Privacy & Security.

## Tech

Built with Swift 6 + SwiftUI + GRDB. Uses ScreenCaptureKit, Accessibility APIs, and AppleScript for context extraction.

## License

MIT
