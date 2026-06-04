# ezclip — Product Requirements

> **A context-aware screenshot curator for designers. Save inspiration without losing the source.**

---

## Vision

Designers collect inspiration obsessively. They screenshot websites, songs, app UIs, typography, color palettes — then dump them into camera rolls, folders called "inspo final v3," or Figma moodboards. Days later, a screenshot is a dead image. What was that website? What song was playing? Which app was that from?

**ezclip makes every screenshot self-contained.** A single hotkey captures the screen AND the context — the URL, the song name, the source app, the file path. The screenshot isn't just an image anymore; it's a reference you can act on.

The product is NOT an AI tool. It's a curation tool. The intelligence is in the metadata, not in generating anything. It's fast, local, and gets out of your way.

---

## Target User

**Primary:** Visual designers (UI/UX, graphic, web) who maintain inspiration libraries.
**Secondary:** Anyone who bookmarks things visually — developers referencing UI patterns, PMs collecting competitor screenshots, creative directors building moodboards.

---

## Core Experience

1. **See something inspiring** — a website, a Spotify track, a Figma file, an app UI.
2. **Double-tap ⌘⌘** — ezclip captures the frontmost window as a screenshot.
3. **Context is auto-extracted** — URL, song/artist/album, file name, app name, timestamp.
4. **Everything saved locally** — browsable library with search, tags, collections.
5. **Act on it later** — open the URL in browser, play the song in Spotify, open the file in Finder.

That's it. No AI. No cloud. No friction.

---

## Current Status: v0.1 MVP (June 2026)

**What works today:**

| Feature | Status |
|---|---|
| ⌘⌘ global hotkey capture | ✅ |
| Screenshot (frontmost window) | ✅ |
| Context extraction (Safari, Chrome, Arc) | ✅ URL, page title, favicon |
| Context extraction (Spotify, Apple Music) | ✅ Song, artist, album |
| Context extraction (Figma) | ✅ File name, page name |
| Auto-tagging | ✅ Domain, app name, artist |
| Library (grid view, search, filter by context type) | ✅ |
| Menu bar popover + Dock app | ✅ |
| Collections (create, assign captures) | ✅ |
| Local storage (SQLite + PNG files) | ✅ |
| Scrolling screenshot (browser full-page) | ⚠️ v1 hack (AppleScript, visible flicker) |
| App icon | ⚠️ Placeholder SF Symbol |
| Code signing / notarization | ❌ |

**What's deliberately NOT in v0.1:**
- AI features (auto-tagging via vision models, summaries, search-by-description)
- Cloud sync
- Browser extensions
- iOS/iPad companion
- Video/GIF capture
- Color palette extraction
- Typography detection

---

## Planned Roadmap

### v0.2 — Polish & Reliability
- [ ] Proper app icon
- [ ] Code signing + notarization (no "unidentified developer" warning)
- [ ] Smooth scrolling screenshots (browser extension or native WebKit approach)
- [ ] Firefox browser support
- [ ] Custom hotkey configuration in preferences
- [ ] Export as moodboard (single image grid)
- [ ] Export captures as CSV/JSON catalog
- [ ] Quick Look preview in library
- [ ] Dark mode polish

### v0.3 — Organization & Power Features
- [ ] Smart collections (auto-group by domain, app, date range)
- [ ] Tag suggestions based on existing tags
- [ ] Duplicate detection (same URL already captured?)
- [ ] Batch actions (tag multiple, move to collection, delete)
- [ ] Capture from multiple displays correctly
- [ ] Keyboard shortcuts for library navigation
- [ ] Drag & drop captures to other apps (Figma, Notion)

### v1.0 — Distribution
- [ ] Homebrew cask
- [ ] Auto-update (Sparkle framework)
- [ ] Onboarding flow (permissions, first capture walkthrough)
- [ ] Proper website/landing page
- [ ] Basic analytics (opt-in, privacy-respecting)

### v2.0 — Ecosystem
- [ ] Share captures via link (generate a share URL with image + metadata)
- [ ] Teams/Shared libraries (shared collection with teammates)
- [ ] Figma plugin (paste captures directly into Figma files)
- [ ] iOS companion app (view library on the go)
- [ ] iCloud sync (optional, encrypted)

### Maybe / Later
- Color palette extraction from captures
- Typography detection (what font is that?)
- OCR text search within screenshots
- Video capture (record the interaction, not just the screenshot)
- Integration with design tools (Figma, Sketch, Framer)

---

## Design Principles

1. **Fast as fuck.** Capture must feel instant. Library must load in under 200ms. No spinner for basic operations.
2. **Local-first.** Everything stored on disk. No account required. No cloud dependency. Your inspiration library is yours.
3. **Context-aware, not AI-powered.** The product's intelligence is in metadata extraction, not generation. We don't summarize, generate, or "enhance." We capture and organize.
4. **Invisible until needed.** Lives in the menu bar. One hotkey. Doesn't interrupt flow. Library appears when you want to browse.
5. **Designer-quality aesthetics.** Every pixel matters. The library should feel like a well-designed product, not a developer tool.

---

## Competitive Landscape

| Tool | What it does | How ezclip differs |
|---|---|---|
| **CleanShot X** | Screenshot annotation + recording | No context extraction, no library/organization |
| **Eagle** | Design asset management | Heavy, subscription, Windows-centric, no hotkey capture |
| **Are.na** | Visual bookmarking | Web-based, manual upload, no system-level capture |
| **Pinterest** | Visual discovery | Platform-locked, algorithm-driven, not a personal tool |
| **Raindrop.io** | Bookmark manager | Link-first, not visual-first, no screenshot capture |
| **Codex Appshots** | AI context injection | AI-focused, sends to LLM thread not a library, macOS-only |

ezclip sits at the intersection of **screenshot tool** + **bookmark manager** + **inspiration library**, optimized for speed and context-awareness.

---

## Success Metrics (when we measure)

- **Daily active captures:** Are people using the hotkey regularly?
- **Library retention:** Do captured items get revisited or do they rot?
- **Context extraction accuracy:** What % of captures have correct URL/song/etc?
- **Time-to-first-capture:** How fast from download to first ⌘⌘?
- **NPS / word of mouth:** Are designers telling other designers?

---

## Appendix: Context Extraction Strategy

Not all apps expose metadata the same way. Our approach per app:

| App | Method | Reliability |
|---|---|---|
| Safari | AppleScript (`URL of front document`) | High |
| Chrome | AppleScript (`URL of active tab`) | High |
| Arc | AppleScript + window title parsing | Medium |
| Firefox | AppleScript (planned v0.2) | Medium |
| Spotify | AppleScript (`current track` properties) | High |
| Apple Music | AppleScript (`current track` properties) | High |
| Figma | Window title parsing (`File — Page — Figma`) | Medium |
| Finder | AppleScript (`target of front window`) | High |
| VS Code / Xcode | Window title parsing | Medium |
| Generic apps | Window title + bundle ID | Always works |

**Long-term:** Move from AppleScript to Accessibility API for more reliable, faster extraction. AppleScript is slow (~300-500ms) and pops permission dialogs.
