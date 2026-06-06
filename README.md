# ezclip

**Save screenshots with context. No more dead images in your camera roll.**

Double-tap ⌘⌘ (Command key) in any app and ezclip captures a screenshot — plus the link, song name, or file path that goes with it. Built for designers collecting inspiration, researchers bookmarking findings, and anyone tired of screenshot folders full of mystery images.

## Features

- **⌘⌘ to capture** — double-tap the left Command key. Works in any app, instantly.
- **Saves the source** — website URL • page title • song + artist • Figma file • Finder path. ezclip remembers where everything came from.
- **Full-page scrolling captures** — for Safari, Chrome, and Zen Browser. Get the whole page, not just the viewport.
- **Auto-tags everything** — domain names, app names, artists become searchable tags automatically.
- **Browse your library** — grid view with search and type filters. Click any capture to see details, copy links, add notes.
- **Keyboard-friendly** — arrow keys to flip through captures, Esc to dismiss. No mouse required.
- **Menu bar + Dock** — always there when you need it, hidden when you don't.
- **100% local** — nothing leaves your Mac. Your data lives at `~/Library/Application Support/ezclip/`. No cloud, no accounts, no AI.

## What gets captured

| App | Saved context |
|---|---|
| Safari, Chrome, Arc, Zen | URL, page title, favicon |
| Spotify, Apple Music | Song, artist, album (from window title — captures what you're looking at) |
| Figma | File name, page name |
| Finder | Current folder path |
| Terminal, VS Code, anything else | App name, window title, timestamp |

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel

## Install

1. Download the latest DMG from [Releases](https://github.com/KohliNaman/ezclip/releases/latest)
2. Open the DMG and drag **ezclip** to your Applications folder
3. Launch ezclip — first time, **right-click → Open** to bypass Gatekeeper
4. Grant **Screen Recording** and **Accessibility** permissions when prompted

## How to use

- **⌘⌘** (double-tap left Command) → capture current window with context
- Click any capture in the grid → detail view with copy links, notes, metadata
- **← → arrow keys** → flip through captures in detail view
- **Esc** or click outside → close detail view
- Menu bar icon or Dock → open library anytime

## Permissions

ezclip needs two permissions:

- **Screen Recording** — to capture window screenshots (System Settings → Privacy & Security → Screen Recording)
- **Accessibility** — to detect the ⌘⌘ hotkey and read window titles (System Settings → Privacy & Security → Accessibility)

You'll be prompted on first launch. Manage these anytime in System Settings.

## Why ezclip

macOS screenshots are dumb — they save pixels and nothing else. A week later you can't remember which website that cool design was from, or what song was playing. ezclip saves the context with the image. No cloud, no subscriptions, no AI — just a fast, local tool that does one thing well.

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
