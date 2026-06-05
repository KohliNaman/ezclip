# ezclip

**Save screenshots with context. No more dead images in your camera roll.**

Double-tap ⌘⌘ (Command key) in any app and ezclip captures a screenshot — plus the link, song name, or file path that goes with it. Built for designers, researchers, and anyone who collects inspiration.

## What it does

- **⌘⌘ to capture** — double-tap the left Command key. Works in any app.
- **Saves the source** — website URL, page title, song + artist, Figma file name, folder path. ezclip remembers where things came from.
- **Full-page scrolling captures** — for Safari, Chrome, and Zen Browser
- **Auto-tags everything** — domain names, app names, artists become searchable tags
- **Local library** — browse, search, filter by type. Add notes to captures.
- **Gallery view** — arrow keys to flip through captures. Keyboard-friendly.
- **Menu bar + Dock** — always there when you need it, hidden when you don't
- **100% local** — nothing leaves your Mac. Data lives in `~/Library/Application Support/ezclip/`

## What it captures

| App | Saves |
|---|---|
| Safari, Chrome, Arc, Zen | URL, page title, favicon |
| Spotify, Apple Music | Song, artist, album |
| Figma | File name, page name |
| Finder | Current folder path |
| Terminal, VS Code, etc. | App name, window title, timestamp |

## Requirements

- macOS 14 (Sonoma) or later
- Works on Apple Silicon and Intel Macs

## Install

1. Download the latest DMG from [Releases](https://github.com/KohliNaman/ezclip/releases/latest)
2. Open the DMG and drag **ezclip** to your Applications folder
3. Launch ezclip (right-click → Open the first time to bypass Gatekeeper)
4. Grant **Screen Recording** and **Accessibility** permissions when prompted

## Usage

- **Double-tap ⌘** (left Command) to capture the current window
- Click any capture in the grid to see details, copy links, add notes
- **Arrow keys** to browse captures in gallery mode
- **Escape** or click the image to close detail view
- Use the menu bar icon or Dock to open the library anytime

## Why ezclip?

macOS screenshots are dumb — they save pixels and nothing else. A week later you can't remember which website that cool design was from, or what song was playing. ezclip saves the context along with the image. No cloud, no subscriptions, no AI — just a fast, local tool that does one thing well.

## Permissions

ezclip needs two permissions to work:

- **Screen Recording** — to capture window screenshots (System Settings → Privacy & Security → Screen Recording)
- **Accessibility** — to detect the ⌘⌘ hotkey and read window titles (System Settings → Privacy & Security → Accessibility)

You'll be prompted on first launch. You can manage these anytime in System Settings.

## Building from source

```bash
git clone https://github.com/KohliNaman/ezclip.git
cd ezclip
brew install xcodegen
xcodegen generate
open ezclip.xcodeproj
```

Requires Xcode 16+ and Swift 6.

## License

MIT
