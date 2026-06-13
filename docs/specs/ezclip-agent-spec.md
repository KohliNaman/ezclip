# ezclip Technical Architecture

This document describes the current implementation shape for future agents and contributors. It is not a backlog.

## Build System

ezclip is an XcodeGen-managed macOS app. Edit `project.yml`, then run:

```sh
xcodegen generate
```

The main app target depends on:

- `GRDB` for SQLite persistence.
- `ezclip-bridge`, a bundled native messaging host for browser extension design context.

## Capture Pipeline

The normal capture path is staged for latency:

1. `HotkeyManager` detects double-left-Command.
2. `CaptureOrchestrator` starts `CapturePipeline`.
3. `CaptureOverlay` shows immediately.
4. `CaptureEngine` captures the frontmost window.
5. `ImageStorageManager` writes screenshot and thumbnail PNGs.
6. `CaptureRepository` inserts the minimal capture row.
7. `ContextResolverEngine` resolves URL/app/music/design metadata with bounded latency.
8. The repository updates the existing capture and replaces generated tags.

Do not add blocking network, extension, or scrolling work before the minimal capture insert.

## Context Resolution

Resolvers are selected by bundle ID:

- Safari: AppleScript URL/title.
- Chrome and Helium: Chromium AppleScript/session/profile strategy.
- Zen and Firefox: Firefox sessionstore parsing with active-title matching.
- Spotify and Apple Music: music metadata.
- Figma: window-title parsing.
- Finder/generic apps: file path or app/window context.

If a resolver cannot return a URL, the engine falls back to URL extraction from the window title.

## Design Context

Browser extensions continuously send active-tab design metadata through native messaging. ezclip reads the latest local payload and attaches it only when URL and freshness checks pass.

The extension path enriches screenshots after the capture exists. It must never be required for core screenshot saving.

## Storage

The SQLite database is stored under:

```sh
~/Library/Application Support/ezclip/ezclip.sqlite
```

Image files, thumbnails, favicons, and album art are also local app-support files. Do not commit user data from this directory.

## Tests

Swift tests live in `Tests/` and JavaScript extractor tests live in `BrowserExtensions/tests/`.

```sh
node --test BrowserExtensions/tests/extractor.test.js
xcodebuild test -project ezclip.xcodeproj -scheme ezclip -destination "platform=macOS,arch=arm64"
```

For capture changes, add tests for parser/repository behavior and manually verify real hotkey capture in at least one generic app and one browser.
