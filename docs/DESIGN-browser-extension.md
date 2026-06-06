# Browser Extension Bridge — Design Document

> Status: **Design only** — not implemented. See Issue #5.

## Goal

Extract rich context from browser tabs that AppleScript and accessibility APIs can't access:
- **Current URL** (already possible via AppleScript for Safari/Chrome, sessionstore for Zen)
- **Scroll position** — which part of the page the user is viewing
- **Fonts** — font-family, font-size, font-weight of visible text elements
- **Colors** — text color, background color, accent colors
- **Icons** — favicon, apple-touch-icon, SVG icons used on the page
- **CSS custom properties** — design tokens (`--color-primary`, `--font-sans`, etc.)
- **Selected element** — if the user has right-clicked / inspected a specific element

## Architecture

```
┌─────────┐     Native Messaging      ┌──────────────────┐
│ ezclip  │ ◄────────────────────────► │ Browser Extension │
│ (Swift) │     stdin/stdout JSON      │   (JavaScript)    │
└─────────┘                            └──────────────────┘
     │                                         │
     │  writes to                               │  reads from
     ▼                                         ▼
┌─────────────────┐                  ┌─────────────────────┐
│ ~/Library/.../  │                  │ chrome.tabs.query() │
│ NativeMessaging │                  │ window.getComputed  │
│ Hosts/          │                  │ Style()             │
└─────────────────┘                  └─────────────────────┘
```

### Components

#### 1. Native Messaging Host (Swift)

A small Swift binary bundled inside `ezclip.app/Contents/MacOS/`. Communicates with the browser extension via stdin/stdout using the [Chrome Native Messaging protocol](https://developer.chrome.com/docs/apps/native-messaging/).

**Location on disk:**
```
ezclip.app/Contents/MacOS/ezclip-bridge
```

**Registry manifest** (per browser, written on app launch):
```json
// ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.namaankohli.ezclip.json
{
  "name": "com.namaankohli.ezclip",
  "description": "ezclip browser bridge",
  "path": "/Applications/ezclip.app/Contents/MacOS/ezclip-bridge",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://<extension-id>/"]
}
```

**Protocol:** 4-byte LE uint32 length prefix + UTF-8 JSON payload. Bidirectional.

**Request** (ezclip → extension):
```json
{
  "action": "extract",
  "include": ["url", "scroll", "fonts", "colors", "icons", "tokens"]
}
```

**Response** (extension → ezclip):
```json
{
  "url": "https://example.com",
  "title": "Page Title",
  "scrollX": 0,
  "scrollY": 450,
  "viewportHeight": 900,
  "fonts": [
    {"family": "Inter", "size": "16px", "weight": "400", "element": "body"},
    {"family": "Inter", "size": "32px", "weight": "700", "element": "h1"}
  ],
  "colors": [
    {"type": "text", "value": "#1a1a1a"},
    {"type": "background", "value": "#ffffff"},
    {"type": "accent", "value": "#3b82f6"}
  ],
  "tokens": [
    {"name": "--color-primary", "value": "#3b82f6"},
    {"name": "--font-sans", "value": "'Inter', sans-serif"}
  ]
}
```

#### 2. Browser Extension (JavaScript)

A minimal WebExtension with:
- `manifest.json` — permissions: `activeTab`, `nativeMessaging`, `scripting`
- `background.js` — listens for native messages, injects content script
- `content.js` — extracts page data and returns it

**Permissions needed:**
```json
{
  "permissions": ["activeTab", "nativeMessaging", "scripting"],
  "host_permissions": ["<all_urls>"]
}
```

**Content script extraction:**
```javascript
// Get computed styles of all visible text elements
const elements = document.querySelectorAll('p, h1, h2, h3, h4, h5, h6, span, a, li, td, th');
const fonts = [];
const seen = new Set();

elements.forEach(el => {
  const style = window.getComputedStyle(el);
  const family = style.fontFamily.split(',')[0].trim().replace(/['"]/g, '');
  const key = `${family}-${style.fontSize}-${style.fontWeight}`;
  if (!seen.has(key) && el.textContent.trim().length > 20) {
    seen.add(key);
    fonts.push({
      family,
      size: style.fontSize,
      weight: style.fontWeight
    });
  }
});

// Extract CSS custom properties from :root
const rootStyles = window.getComputedStyle(document.documentElement);
const tokens = [];
for (let i = 0; i < rootStyles.length; i++) {
  const prop = rootStyles[i];
  if (prop.startsWith('--')) {
    tokens.push({ name: prop, value: rootStyles.getPropertyValue(prop) });
  }
}
```

#### 3. ezclip Integration (Swift)

In `ContextResolver.swift` → new `BrowserExtensionResolver`:

```swift
struct BrowserExtensionResolver: AppContextResolver {
    let supportedBundleIds = [
        "com.google.Chrome",
        "org.mozilla.firefox",
        "app.zen-browser.zen"
    ]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let bridge = NativeMessagingBridge.shared
        let result = try await bridge.extract(bundleId: bundleId)
        return ResolvedContext(
            contextType: .website,
            url: result.url,
            pageTitle: result.title,
            // Extended context — stored as JSON in notes or new fields
            ...
        )
    }
}
```

### Browser Support

| Browser | Native Messaging | Extension API | Notes |
|---------|-----------------|---------------|-------|
| Chrome | ✅ | Manifest V3 | Primary target |
| Firefox | ✅ (different manifest path) | Manifest V3/V2 | Different manifest location |
| Zen | ✅ (Firefox-based) | Manifest V2 | Shares Firefox extension |
| Arc | ✅ (Chromium-based) | Manifest V3 | Shares Chrome extension |
| Safari | ❌ (Safari App Extension) | Different API | Needs separate implementation |
| Orion | ❌ | N/A | No extension API |

### Why Not AppleScript / Accessibility APIs

| Data | AppleScript | Accessibility | Extension |
|------|------------|---------------|-----------|
| URL | ✅ (most browsers) | ❌ | ✅ |
| Page title | ✅ | ✅ (AXTitle) | ✅ |
| Scroll position | ❌ | ❌ | ✅ |
| Fonts | ❌ | ❌ | ✅ |
| Colors | ❌ | ❌ | ✅ |
| CSS tokens | ❌ | ❌ | ✅ |
| Selected element | ❌ | Partial (AXFocusedUIElement) | ✅ |

AppleScript can get URL and title for Safari/Chrome. Accessibility can get window title and focused element. But neither can read CSS, fonts, colors, or precise scroll position. The browser extension is the only path to rich design context.

### Signing & Distribution

- The native messaging host binary is bundled inside the .app — **no separate notarization needed**
- The browser extension is hosted on the Chrome Web Store / Firefox Add-ons (or sideloaded)
- For sideloading: users load unpacked extension in `chrome://extensions` with Developer Mode
- Firefox: temporary extension via `about:debugging` or signed `.xpi` via Mozilla Add-ons

### Implementation Plan (Future)

1. Build `ezclip-bridge` Swift CLI that reads/writes Native Messaging protocol
2. Create Chrome/Firefox extension with content script
3. Wire `ezclip-bridge` into ezclip's `ContextResolverEngine`
4. Write registry manifests on app launch
5. Test on Chrome → Firefox → Zen → Arc
6. Publish extensions to stores

### Open Questions

- **Scroll capture integration**: when doing a scrolling capture, should we extract fonts/colors from each scroll position or just the initial view?
- **Storage**: extend `Capture` model with JSON `designContext` field, or store as markdown note?
- **Performance**: content script extraction takes 10-50ms on typical pages. Acceptable for manual trigger.
- **Safari**: needs a separate Safari App Extension (different API, Xcode project, signing). Defer to v2.
