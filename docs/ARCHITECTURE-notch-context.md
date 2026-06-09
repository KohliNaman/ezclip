# ezclip: Notch Overlay + Context Extraction Architecture

## Data Flow (capture pipeline)

```
⌘⌘ double-tap
    │
    ▼
HotkeyMonitor (CGEvent tap)
    │
    ▼
CaptureOrchestrator.capture()
    │
    ├─► ScreenCaptureManager.captureFrontmostWindow()
    │       → returns (CGImage, WindowInfo)
    │
    ├─► ImageStorageManager.saveScreenshot()
    │       → returns (fullPath, thumbPath)
    │
    ├─► ClipboardManager.copyToClipboard()
    │
    ├─► ContextResolverEngine.resolve(bundleId, windowTitle)
    │       → dispatches to per-browser resolver
    │       → returns ResolvedContext (url, pageTitle, songName, etc.)
    │
    ├─► DatabaseManager.write { capture.insert() }
    │
    ├─► showNotification()
    │
    └─► CaptureOverlay.shared.show(context, thumbnail, appName, bundleId)
            → NSPanel at .mainMenu + 3
            → SwiftUI pill with app icon + context badge
            → auto-expand → auto-dismiss
```

## Component Architecture

### Context Resolvers (Sources/ContextResolvers/)

```
ContextResolverEngine (dispatcher)
    │
    ├── SafariResolver        → AppleScript (only browser that needs it)
    ├── ChromiumResolver      → Binary plist sessionstore
    │       Chrome, Brave, Edge, Arc, Vivaldi, Opera, Orion, DDG
    ├── FirefoxResolver       → mozLz4 sessionstore (shared LZ4 util)
    ├── ZenResolver           → mozLz4 sessionstore (shared LZ4 util)
    ├── SpotifyResolver       → Window title parsing
    ├── AppleMusicResolver    → AppleScript
    └── FigmaResolver         → AppleScript

SessionstoreUtils (shared utility)
    ├── findRecoveryFile()    → locates sessionstore-backups/recovery.jsonlz4
    ├── decompressMozLz4()    → pure-Swift LZ4 block decompressor
    └── extractActiveURL()    → JSON path traversal
```

### Capture Overlay (Sources/UI/CaptureOverlay.swift)

```
NotchPanel (NSPanel subclass)
    ├── styleMask: [.borderless, .nonactivatingPanel, .hudWindow]
    ├── level: .mainMenu + 3  (above menu bar, in notch region)
    ├── canBecomeKey: false (override)
    ├── canBecomeMain: false (override)
    └── collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

OverlayViewModel (ObservableObject)
    ├── phase: hidden → peek → expanded → dismissed
    ├── appIcon, appName, contextBadge, contextIcon
    ├── screenshotThumbnail
    └── configure(from: ResolvedContext)

NotchOverlayView (SwiftUI View)
    ├── ZStack: NotchPillShape background + content
    ├── Peek state: small pill (120×32, cornerRadius 16)
    │       app icon + app name
    ├── Expanded state: large pill (280×140, cornerRadius 20)
    │       app icon + app name + context badge + thumbnail
    ├── Animation: spring(response: 0.42, dampingFraction: 0.8) on open
    │             spring(response: 0.45, dampingFraction: 1.0) on close
    ├── Morphing shape via animatableData on corner radius
    └── .compositingGroup() for GPU-layer performance

NotchPillShape (Shape + animatableData)
    └── RoundedRectangle with smooth corner radius transition
```

## Current Known Issues

1. ~~CaptureOverlay has Swift 6 compile errors~~ → fixed in b1f460f
2. ~~browserName ordering in ResolvedContext init~~ → fixed in 89d5ec9
3. ~~contentTransition iOS API~~ → removed in b1f460f
4. Need to verify the CaptureOverlay actually shows correctly at .mainMenu + 3
5. The CGWindowLevelForKey(.mainMenuWindow) + 3 needs testing on real MacBook

## macOS API Constraints (macOS 14+ target)

| API | Availability | Notes |
|-----|-------------|-------|
| NSScreen.safeAreaInsets | macOS 12+ | Detects notch presence |
| NSScreen.auxiliaryTopLeftArea | macOS 12+ | Notch width calculation |
| NSPanel, CGWindowLevelForKey | macOS 10.0+ | Core overlay mechanism |
| .spring() animation | macOS 14+ | SwiftUI spring animations |
| .sensoryFeedback | macOS 14+ | Haptic feedback |
| .compositingGroup() | macOS 14+ | GPU layer flattening |
| PropertyListSerialization | macOS 10.0+ | Binary plist reading |
| LZ4 decompression | Pure Swift | No system dependency |
| NSAppleScript | macOS 10.0+ | Safari/Figma/AppleMusic only |

## What NOT to use (iOS-only, unavailable on macOS 14)

- `.contentTransition(.scale(...))` — iOS 17+ API
- `.matchedGeometryEffect` — unreliable on macOS
- `.animation(.bouncy)` — iOS 17+, use `.spring(dampingFraction:)` on macOS
- `UIApplication` / `UIDevice` — iOS only
- `UIScreen` — iOS only
