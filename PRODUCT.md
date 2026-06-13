# ezclip — Product Requirements

> A local-first screenshot library that keeps the source, design language, and context attached to every capture.

## Vision

Screenshots are useful when taken and frustrating a week later. ezclip turns a screenshot into a reusable reference by saving the image, source URL or app context, design tokens, fonts, colors, buttons, music metadata, and notes in one local library.

The product is not an AI generator. It is a fast capture and curation tool for designers, developers, and researchers who collect visual references while working.

## Core Experience

1. Double-tap the left Command key in any app.
2. A notch-style tray appears immediately while the frontmost window is captured.
3. ezclip saves the screenshot and thumbnail locally.
4. Fast context resolves in the background: app, window title, URL, page title, music, Figma, Finder, and tags.
5. Browser extensions enrich web captures asynchronously with fonts, CSS tokens, colors, scroll position, and rendered button previews.
6. The library lets users search, filter, revisit URLs, copy metadata, and inspect design context.

## Current Feature Set

| Area | Current behavior |
|---|---|
| Capture | Double-Command global hotkey, front-window screenshot, clipboard copy, local PNG storage |
| Feedback | Top-attached notch tray with capture, saved, enriched, and failed states |
| Browsers | Safari via AppleScript; Chrome and Helium via Chromium resolver; Zen and Firefox via sessionstore parsing |
| Design context | Optional Chrome/Helium and Zen/Firefox extensions collect fonts, `@font-face`, colors, CSS variables, scroll data, and buttons |
| Music | Spotify and Apple Music metadata with bounded resolver latency |
| Design apps | Figma window-title parsing and design classification |
| Library | Grid view, search, sidebar context filters, tag filters, collections, notes, detail windows |
| Storage | GRDB SQLite database plus local screenshot, thumbnail, favicon, and album-art files |
| Packaging | XcodeGen project, Debug dev install script, release DMG script, GitHub Actions build/test workflow |

## Architecture

The capture path is staged so slow metadata never blocks saving:

- `HotkeyManager` detects the double-Command gesture.
- `CaptureOrchestrator` delegates to `CapturePipeline`.
- `CaptureOverlay` shows visual feedback immediately.
- `CaptureEngine` captures the frontmost window and `ImageStorageManager` writes image files.
- `CaptureRepository` inserts the minimal capture, then updates context and tags as they resolve.
- `ContextResolverEngine` routes to Safari, Chromium, Zen/Firefox, music, Figma, Finder, or generic fallback resolvers.
- `BrowserDesignContextStore` reads the latest extension payload and attaches it only when fresh and URL-compatible.
- `ezclip-bridge` is the native messaging host used by the browser extensions.

## Browser Extension Requirements

The extensions must never block screenshot capture. They continuously send latest active-tab design context to the native bridge. ezclip matches that payload to a capture by URL and freshness.

Payloads include:

- `url`, `title`, `capturedAt`, and scroll metrics.
- Visible font samples with family, size, weight, selector, sample text, and usage count.
- Accessible `@font-face` CSS so previews can render closer to the original site.
- Prominent text/background colors and root CSS custom properties.
- Up to 12 visible button/link-button previews with sanitized HTML and computed styles.

Safari design enrichment is deferred because it requires a Safari App Extension.

## Product Principles

- **Fast first:** screenshot save and overlay feedback must feel immediate.
- **Local-first:** no account, cloud sync, or remote processing is required.
- **Context-aware:** metadata should make the capture actionable without turning the product into an AI tool.
- **Non-interrupting:** prompts and animations should not break flow.
- **Designer-quality:** the library and detail views should make visual references easy to scan and reuse.

## Release Readiness

Public builds should include:

- A generated `ezclip.xcodeproj` from `project.yml`.
- Passing JS extension tests and Swift unit tests.
- A verified DMG from `./Scripts/build-release.sh`.
- Native messaging manifests written on app launch for Chrome, Helium, Zen, and Firefox.
- Clear install notes for browser extensions and macOS Screen Recording/Accessibility permissions.

## Near-Term Backlog

- Publish signed browser extensions instead of relying only on unpacked/temporary installs.
- Add first-run extension install/onboarding UI.
- Replace deprecated `CGWindowListCreateImage` fallback with a modern ScreenCaptureKit-only path where possible.
- Add duplicate detection and batch tag/collection actions.
- Add notarized Developer ID distribution once signing credentials are available.
