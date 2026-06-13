# Browser Design Context Extension

Status: implemented as unpacked development extensions for Chromium and Firefox-family browsers.

## Purpose

The browser extensions enrich saved web captures with design metadata that native macOS APIs cannot read: visible fonts, accessible `@font-face` declarations, CSS custom properties, prominent colors, scroll position, and rendered button previews.

This data is optional. The screenshot path must remain fast even if an extension is missing, disabled, or unable to inspect the current page.

## Architecture

```
Browser tab -> extension content extractor -> native messaging -> ezclip-bridge -> latest-design-context.json -> capture resolver
```

- `BrowserExtensions/chromium/` is the Manifest V3 extension for Chrome and Helium.
- `BrowserExtensions/firefox/` is the Firefox/Zen-compatible extension.
- `BrowserExtensions/shared/extractor.js` is the canonical extractor; browser-specific copies are kept in sync.
- `BridgeSources/main.swift` implements the native messaging host and atomically writes the latest payload.
- `BrowserDesignContextStore` reads the local payload and attaches it to a capture only when the URL and freshness checks match.

## Native Messaging

The app writes manifests on launch:

- Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.namaankohli.ezclip.json`
- Helium: `~/Library/Application Support/net.imput.helium/NativeMessagingHosts/com.namaankohli.ezclip.json`
- Firefox: `~/Library/Application Support/Mozilla/NativeMessagingHosts/com.namaankohli.ezclip.json`
- Zen: `~/Library/Application Support/zen/NativeMessagingHosts/com.namaankohli.ezclip.json`

Chromium uses the pinned extension ID `aneomelhkigghoclfgmpejhmpgogpfij`. Firefox/Zen use `ezclip-design-context@namaankohli.com`.

## Payload

The bridge stores JSON under ezclip app support. Key fields:

- `url`, `title`, `capturedAt`
- `scroll`: x/y offset, viewport, document height
- `fonts`: family, size, weight, selector, sample text, count
- `fontFaceCSS`: accessible `@font-face` CSS with relative font URLs resolved
- `colors`: role, value, count
- `cssTokens`: CSS custom properties from `:root`
- `buttons`: sanitized preview HTML plus computed dimensions and colors

Payloads are capped so pathological pages cannot bloat the database.

## Testing

Run extractor tests with:

```sh
node --test BrowserExtensions/tests/extractor.test.js
```

Manual checks should cover Chrome, Helium, Zen, and Firefox where installed. After focusing a normal webpage, the latest design-context JSON should update, and a subsequent ezclip capture should show a Design section in the detail view.
