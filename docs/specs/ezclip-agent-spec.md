# ezclip — Technical Change Spec

> For implementation by coding agent. Treat each ticket as an atomic unit of work.
> Priority order: EZCLIP-001 → 002 → 003 → 004 → 005

-----

## EZCLIP-001 · Migrate from SPM executableTarget to XcodeGen project

**Priority:** Critical · Do this before anything else.

### Problem

`Package.swift` declares an `executableTarget`, which is the wrong primitive for a macOS GUI app. Consequences:

- Entitlements (`com.apple.security.device.screen-capture`, `com.apple.security.automation.apple-events`) cannot be declared in SPM — they have to be injected manually into the binary or via the build script. This is fragile and incorrect.
- `@main` + `App` protocol doesn’t work cleanly with SPM executables; `main.swift` is required, which is a less idiomatic SwiftUI entry point.
- Code signing, notarization, and Sparkle (future) all require a proper `.app` bundle with a valid `Info.plist` and entitlements file — none of which SPM manages.
- The `Scripts/build.sh` is doing work that Xcode should own.

### Solution

Use **XcodeGen** to define the project as `project.yml` and generate `ezclip.xcodeproj`. This keeps the project definition human-readable and diffable (no binary xcodeproj soup), while giving the agent a clean, writable format.

### Steps

**1. Install XcodeGen (one-time, not in repo)**

```bash
brew install xcodegen
```

**2. Create `project.yml` in repo root**

```yaml
name: ezclip
options:
  bundleIdPrefix: com.namaankohli
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.4"
  groupSortPosition: top
  createIntermediateGroups: true

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: 6.29.0

targets:
  ezclip:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: Sources
        createIntermediateGroups: true
    resources:
      - path: Resources
    dependencies:
      - package: GRDB
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.namaankohli.ezclip
        PRODUCT_NAME: ezclip
        SWIFT_VERSION: "6.0"
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        # Universal binary — arm64 + x86_64
        ARCHS: $(ARCHS_STANDARD)
        ONLY_ACTIVE_ARCH: NO
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: ""          # agent leaves blank; developer fills in
        CODE_SIGN_IDENTITY: "-"       # ad-hoc signing for now
        INFOPLIST_FILE: Resources/Info.plist
        CODE_SIGN_ENTITLEMENTS: Resources/ezclip.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
      configs:
        Debug:
          ONLY_ACTIVE_ARCH: YES       # fast local builds
          SWIFT_OPTIMIZATION_LEVEL: "-Onone"
        Release:
          SWIFT_OPTIMIZATION_LEVEL: "-O"
          DEAD_CODE_STRIPPING: YES

schemes:
  ezclip:
    build:
      targets:
        ezclip: all
    run:
      config: Debug
    archive:
      config: Release
```

**3. Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.namaankohli.ezclip</string>
  <key>CFBundleName</key>
  <string>ezclip</string>
  <key>CFBundleDisplayName</key>
  <string>ezclip</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleExecutable</key>
  <string>$(EXECUTABLE_NAME)</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>                            <!-- hides from Cmd+Tab, Dock by default -->
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <!-- Permission prompt strings shown to the user -->
  <key>NSScreenCaptureUsageDescription</key>
  <string>ezclip needs screen recording permission to capture window screenshots.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>ezclip uses AppleScript to extract context from Safari, Spotify, and other apps.</string>
  <!-- Accessibility is requested programmatically via AXIsProcessTrusted(),
       not declared in Info.plist. No key needed here. -->
</dict>
</plist>
```

> **Note on `LSUIElement`:** Setting this to `true` hides the Dock icon by default. The app already manages its own Dock visibility toggle in SwiftUI (`NSApp.setActivationPolicy`). Keep it consistent with whatever the current code does — if the app already has a Dock toggle, this is correct. If you want Dock icon on by default, set to `false`.

**4. Create `Resources/ezclip.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- Required for ScreenCaptureKit -->
  <key>com.apple.security.device.screen-capture</key>
  <true/>
  <!-- Required for AppleScript against other apps -->
  <key>com.apple.security.automation.apple-events</key>
  <true/>
  <!-- Required for Accessibility API (CGEvent tap, AX tree reads) -->
  <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
  <array>
    <string>com.apple.ak.anisette.production</string>
  </array>
  <!-- App Sandbox: DISABLED for v0.1 -->
  <!-- Sandboxing will block CGEvent tap (global hotkey) and AppleScript.
       Enable sandbox in a later version once AX API replaces AppleScript
       and the hotkey moves to a registered service. -->
  <key>com.apple.security.app-sandbox</key>
  <false/>
  <!-- Hardened runtime exceptions needed for CGEvent global tap -->
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <false/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <false/>
</dict>
</plist>
```

**5. Create `Resources/` directory and move any existing assets there**

If there’s an `Assets.xcassets` or app icon anywhere in Sources, move it to `Resources/`. The `project.yml` above references `Resources/` for all non-code assets.

**6. Update entry point to use `@main`**

If `Sources/main.swift` exists, replace it with the idiomatic SwiftUI entry:

```swift
// Sources/App.swift  (delete main.swift)
import SwiftUI

@main
struct EzclipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar scene
        MenuBarExtra("ezclip", systemImage: "camera.viewfinder") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        // Main library window (opened from menu bar or Dock)
        WindowGroup("Library", id: "library") {
            LibraryView()
        }
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}  // remove File > New
        }

        // Preferences window
        Settings {
            PreferencesView()
        }
    }
}
```

**7. Generate the project**

```bash
# From repo root
xcodegen generate
```

This produces `ezclip.xcodeproj`. Commit both `project.yml` and the generated `ezclip.xcodeproj`.

**8. Delete `Package.swift` and `Scripts/build.sh`**

`Package.swift` is replaced by `project.yml` + Xcode’s native SPM integration. The build script is replaced by `xcodebuild`. Add a new `Scripts/build-release.sh` (see EZCLIP-004).

**9. Add `ezclip.xcodeproj/xcuserdata` to `.gitignore`**

```gitignore
# Xcode
ezclip.xcodeproj/xcuserdata/
ezclip.xcodeproj/project.xcworkspace/xcuserdata/
*.xccheckout
*.moved-aside
DerivedData/
*.hmap
*.ipa
*.xcarchive
```

### Acceptance Criteria

- [ ] `xcodegen generate && xcodebuild build` exits 0 on macOS 14
- [ ] App launches from Xcode with Run (⌘R)
- [ ] Screen Recording and Accessibility permission prompts appear on first launch with the correct usage strings
- [ ] `Package.swift` and `Scripts/build.sh` are deleted
- [ ] `project.yml`, `Resources/Info.plist`, `Resources/ezclip.entitlements` are committed
- [ ] `xcuserdata` is gitignored

-----

## EZCLIP-002 · Enable universal binary (arm64 + x86_64)

**Priority:** High · Included in project.yml above, but calling it out explicitly.

### Problem

README and release notes say “Apple Silicon only.” ScreenCaptureKit, AX API, CGEvent taps, and AppleScript all work on Intel Macs running macOS 14. This is an artificial restriction that cuts out a real percentage of the designer market (many still on Intel MacBooks).

The restriction almost certainly exists because `Scripts/build.sh` compiled for `arm64` only without a universal target.

### Solution

In `project.yml` (already included in EZCLIP-001):

```yaml
ARCHS: $(ARCHS_STANDARD)   # arm64 + x86_64
ONLY_ACTIVE_ARCH: NO        # in Release; YES in Debug for speed
```

For `xcodebuild` in CI and release builds:

```bash
xcodebuild archive \
  -project ezclip.xcodeproj \
  -scheme ezclip \
  -configuration Release \
  -archivePath build/ezclip.xcarchive \
  ONLY_ACTIVE_ARCH=NO
```

### Update README

Remove this line from Requirements:

```
- Apple Silicon (M1/M2/M3/M4)
```

Replace with:

```
- macOS 14 Sonoma or later (Apple Silicon and Intel)
```

### Acceptance Criteria

- [ ] `lipo -info build/ezclip.app/Contents/MacOS/ezclip` returns `Architectures in the fat file: arm64 x86_64`
- [ ] README requirements section updated

-----

## EZCLIP-003 · Restructure Sources/ into logical groups

**Priority:** Medium · Do after EZCLIP-001 is working.

### Problem

All Swift files sit in a flat `Sources/` directory. At v0.1 with ~10 files this is fine. By v0.3 with 25+ files it becomes unnavigable. Establish the structure now so future work lands in the right place.

### Solution

Reorganise into the following folder structure inside `Sources/`. These are **Xcode groups** (folders on disk), not separate SPM targets — everything remains a single target.

```
Sources/
├── App/
│   ├── App.swift                    # @main entry point (from EZCLIP-001)
│   ├── AppDelegate.swift            # NSApplicationDelegate if needed
│   └── AppState.swift               # @Observable global state
│
├── Capture/
│   ├── CaptureEngine.swift          # ScreenCaptureKit orchestration
│   ├── HotkeyMonitor.swift          # CGEvent tap, double-⌘ detection
│   └── ScrollCapture.swift          # Scrolling screenshot logic
│
├── ContextResolvers/
│   ├── ContextResolver.swift        # Protocol definition
│   ├── SafariResolver.swift
│   ├── ChromeResolver.swift
│   ├── ArcResolver.swift
│   ├── SpotifyResolver.swift
│   ├── AppleMusicResolver.swift
│   ├── FigmaResolver.swift
│   ├── FinderResolver.swift
│   └── GenericResolver.swift        # Fallback: app name + window title
│
├── Storage/
│   ├── Database.swift               # GRDB setup, migrations
│   ├── Models/
│   │   ├── Capture.swift            # GRDB record type
│   │   ├── Tag.swift
│   │   └── Collection.swift
│   └── Repositories/
│       ├── CaptureRepository.swift
│       └── CollectionRepository.swift
│
└── UI/
    ├── MenuBar/
    │   └── MenuBarView.swift
    ├── Library/
    │   ├── LibraryView.swift
    │   ├── CaptureGridView.swift
    │   ├── CaptureDetailView.swift
    │   └── FilterPillsView.swift
    ├── Preferences/
    │   └── PreferencesView.swift
    └── Components/
        └── (shared SwiftUI components)
```

### Migration Steps

1. Create the folder structure above inside `Sources/`
1. Move each existing `.swift` file to its logical home
1. Run `xcodegen generate` to regenerate `ezclip.xcodeproj` with the new groups
1. Fix any import errors (there should be none — same module, same target)
1. Build and confirm green

### Acceptance Criteria

- [ ] `Sources/` matches the structure above (±files that already exist under different names — agent should use judgement to map existing files to correct groups)
- [ ] `xcodebuild build` exits 0 after restructure
- [ ] No orphaned files in root `Sources/`

-----

## EZCLIP-004 · Replace build.sh with proper xcodebuild release pipeline

**Priority:** Medium · Replaces the deleted `Scripts/build.sh`.

### Create `Scripts/build-release.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION=$(defaults read "$(pwd)/Resources/Info.plist" CFBundleShortVersionString)
ARCHIVE_PATH="build/ezclip.xcarchive"
APP_PATH="build/ezclip.app"
DMG_PATH="build/ezclip-v${VERSION}.dmg"

echo "==> Building ezclip v${VERSION}"

# Clean
rm -rf build/
mkdir -p build/

# Archive (universal binary, release config)
xcodebuild archive \
  -project ezclip.xcodeproj \
  -scheme ezclip \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  ONLY_ACTIVE_ARCH=NO \
  | xcpretty

# Export .app from archive (no code signing for now — ad-hoc)
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath build/ \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  | xcpretty

# Package as DMG using create-dmg
# brew install create-dmg  (one-time)
create-dmg \
  --volname "ezclip" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --icon "ezclip.app" 180 170 \
  --hide-extension "ezclip.app" \
  --app-drop-link 480 170 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$APP_PATH"

echo "==> Done: $DMG_PATH"
```

### Create `Scripts/ExportOptions.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>     <!-- change to "app-store" for MAS later -->
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
```

### Update `.github/workflows/build.yml`

Replace the current workflow with:

```yaml
name: Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14          # or self-hosted if MacBook runner is set up

    steps:
      - uses: actions/checkout@v4

      - name: Install XcodeGen
        run: brew install xcodegen xcpretty

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Build (Debug, active arch only in CI)
        run: |
          xcodebuild build \
            -project ezclip.xcodeproj \
            -scheme ezclip \
            -configuration Debug \
            -destination "platform=macOS" \
            ONLY_ACTIVE_ARCH=YES \
            | xcpretty && exit ${PIPESTATUS[0]}
```

### Acceptance Criteria

- [ ] `Scripts/build-release.sh` exists and is executable (`chmod +x`)
- [ ] `Scripts/ExportOptions.plist` exists
- [ ] CI workflow uses `xcodebuild` not `./Scripts/build.sh`
- [ ] CI passes on push to main

-----

## EZCLIP-005 · Replace AppleScript context extraction with Accessibility API

**Priority:** High for v0.2 · This is the most impactful UX fix after the architecture migration.

### Problem

Current AppleScript-based extraction adds 300–500ms latency per capture. For a tool whose core promise is “feels instant,” this is a real problem. AppleScript also:

- Requires `NSAppleEventsUsageDescription` and triggers permission dialogs
- Occasionally blocks the main thread if the target app is busy
- Has no structured error type — failures are `NSError` with opaque codes
- Doesn’t work in a sandboxed context (blocking future sandbox adoption)

### Target architecture

Every resolver should implement this protocol:

```swift
// Sources/ContextResolvers/ContextResolver.swift

import AppKit

/// All context resolvers are synchronous — they run off main thread in a Task.
/// Must complete in under 50ms on average. If it can't, throw and fall back
/// to GenericResolver.
protocol ContextResolver {
    /// Returns true if this resolver handles the given app.
    static func canHandle(bundleID: String) -> Bool

    /// Extracts context. Runs on a background thread. Must not block > 200ms.
    func resolve(app: NSRunningApplication, windowTitle: String) async throws -> CaptureContext
}

struct CaptureContext {
    var appName: String
    var windowTitle: String
    var bundleID: String
    var capturedAt: Date = .now
    // Context-specific fields (nil if not applicable)
    var url: URL?
    var pageTitle: String?
    var faviconURL: URL?
    var songTitle: String?
    var artist: String?
    var album: String?
    var albumArtURL: URL?
    var figmaFileName: String?
    var figmaPageName: String?
    var finderPath: String?
    // Auto-generated tags
    var tags: [String] { computeTags() }

    private func computeTags() -> [String] {
        var t: [String] = [appName.lowercased()]
        if let host = url?.host { t.append(host) }
        if let a = artist { t.append(a.lowercased()) }
        return t
    }
}
```

### AX API implementation for browser resolvers

Replace AppleScript URL extraction with direct AX API reads:

```swift
// Sources/ContextResolvers/SafariResolver.swift
import AppKit
import ApplicationServices

struct SafariResolver: ContextResolver {

    static func canHandle(bundleID: String) -> Bool {
        bundleID == "com.apple.Safari"
    }

    func resolve(app: NSRunningApplication, windowTitle: String) async throws -> CaptureContext {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Get focused window
        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard windowResult == .success, let window = windowRef else {
            throw ResolverError.axAttributeUnavailable("kAXFocusedWindow")
        }

        // Traverse: Window → Toolbar → Address bar → AXValue (URL string)
        // Safari's AX tree: AXWindow → AXToolbar → AXTextField[identifier="WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"]
        let urlString = try extractSafariURL(from: window as! AXUIElement)
        let url = URL(string: urlString)

        return CaptureContext(
            appName: "Safari",
            windowTitle: windowTitle,
            bundleID: app.bundleIdentifier ?? "com.apple.Safari",
            url: url,
            pageTitle: windowTitle  // Safari sets window title = page title
        )
    }

    private func extractSafariURL(from window: AXUIElement) throws -> String {
        // Walk the AX tree to find the address bar text field
        var toolbarRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXToolbarButtonAttribute as CFString, &toolbarRef)

        // Safari exposes address bar as a child with role AXTextField
        // and subrole AXSearchField, identifier "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
        guard let urlString = findAddressBarValue(in: window) else {
            throw ResolverError.axAttributeUnavailable("address bar")
        }
        return urlString
    }

    private func findAddressBarValue(in element: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String

            var identifierRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &identifierRef)
            let identifier = identifierRef as? String

            if role == kAXTextFieldRole as String,
               identifier == "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD" {
                var valueRef: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef)
                return valueRef as? String
            }

            // Recurse
            if let found = findAddressBarValue(in: child) { return found }
        }
        return nil
    }
}

enum ResolverError: Error {
    case axAttributeUnavailable(String)
    case appNotReady
    case unsupportedApp
}
```

### Spotify via AX API

Spotify exposes `NowPlaying` properties through its AX tree and through `MediaRemote` framework. The fastest approach is `MediaRemote`:

```swift
// Sources/ContextResolvers/SpotifyResolver.swift
import AppKit
import MediaPlayer    // Available macOS 14+

struct SpotifyResolver: ContextResolver {

    static func canHandle(bundleID: String) -> Bool {
        bundleID == "com.spotify.client"
    }

    func resolve(app: NSRunningApplication, windowTitle: String) async throws -> CaptureContext {
        // MPNowPlayingInfoCenter gives us the current track without AppleScript
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo

        let title  = info?[MPMediaItemPropertyTitle] as? String
        let artist = info?[MPMediaItemPropertyArtist] as? String
        let album  = info?[MPMediaItemPropertyAlbumTitle] as? String

        // Album art
        let artwork = info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
        let image = artwork?.image(at: CGSize(width: 300, height: 300))
        // image is NSImage — save to disk as part of the capture pipeline, not here

        return CaptureContext(
            appName: "Spotify",
            windowTitle: windowTitle,
            bundleID: "com.spotify.client",
            songTitle: title,
            artist: artist,
            album: album
            // albumArtURL set by CaptureEngine after saving image to disk
        )
    }
}
```

> `MPNowPlayingInfoCenter` works for Apple Music too. Use the same approach for `AppleMusicResolver` — just change `canHandle` to `"com.apple.Music"`.

### ContextResolver dispatch

```swift
// Sources/ContextResolvers/ContextResolverDispatcher.swift

struct ContextResolverDispatcher {

    private static let resolvers: [any ContextResolver.Type] = [
        SafariResolver.self,
        ChromeResolver.self,
        ArcResolver.self,
        SpotifyResolver.self,
        AppleMusicResolver.self,
        FigmaResolver.self,
        FinderResolver.self,
    ]

    static func resolve(for app: NSRunningApplication, windowTitle: String) async -> CaptureContext {
        let bundleID = app.bundleIdentifier ?? ""

        for resolverType in resolvers {
            guard resolverType.canHandle(bundleID: bundleID) else { continue }
            let resolver = resolverType.init()
            do {
                return try await resolver.resolve(app: app, windowTitle: windowTitle)
            } catch {
                // Log and fall through to generic
                print("[ContextResolver] \(resolverType) failed: \(error). Falling back.")
            }
        }

        return GenericResolver().resolveGeneric(app: app, windowTitle: windowTitle)
    }
}
```

### Timing contract

Each resolver must complete in < 200ms. Add a timeout wrapper in `CaptureEngine`:

```swift
let context = try await withThrowingTaskGroup(of: CaptureContext.self) { group in
    group.addTask {
        await ContextResolverDispatcher.resolve(for: frontmostApp, windowTitle: windowTitle)
    }
    group.addTask {
        try await Task.sleep(for: .milliseconds(200))
        throw CaptureError.contextTimeout
    }
    let result = try await group.next()!
    group.cancelAll()
    return result
}
// If timeout fires, fall back to GenericResolver result
```

### Remove AppleScript infrastructure

Once all resolvers are migrated to AX API / MediaRemote:

- Delete any `.scpt` files or inline AppleScript strings
- Remove `NSAppleEventsUsageDescription` from `Info.plist`
- Remove `com.apple.security.automation.apple-events` from entitlements

### Acceptance Criteria

- [ ] `ContextResolver` protocol is defined as above
- [ ] `SafariResolver`, `ChromeResolver`, `ArcResolver` use AX API (no AppleScript)
- [ ] `SpotifyResolver`, `AppleMusicResolver` use `MPNowPlayingInfoCenter`
- [ ] `FigmaResolver` and `FinderResolver` use window title parsing + AX API for path
- [ ] `ContextResolverDispatcher` dispatches based on `bundleIdentifier`
- [ ] Each resolver has a 200ms timeout enforced in `CaptureEngine`
- [ ] No inline AppleScript strings remain in any Swift file
- [ ] `NSAppleEventsUsageDescription` removed from `Info.plist` (after full migration)
- [ ] Measured latency from ⌘⌘ press to capture completion is < 150ms (excluding screenshot I/O)

-----

## EZCLIP-006 · Fix README broken links

**Priority:** Low · 5-minute fix, do it now.

In `README.md`, two lines reference `github.com/namaankohli/ezclip` (lowercase). The actual repo is `github.com/KohliNaman/ezclip`. GitHub redirects these but it’s sloppy for a public repo.

Find:

```
https://github.com/namaankohli/ezclip/releases
https://github.com/namaankohli/ezclip.git
```

Replace with:

```
https://github.com/KohliNaman/ezclip/releases
https://github.com/KohliNaman/ezclip.git
```

### Acceptance Criteria

- [ ] No references to `namaankohli` (lowercase) remain in README.md or any markdown file
- [ ] Both links resolve correctly in browser

-----

## Implementation Order

```
EZCLIP-006   →   5 min, unblocks clean repo state
EZCLIP-001   →   hardest, do on a feature branch, test thoroughly
EZCLIP-002   →   already included in EZCLIP-001's project.yml, just verify
EZCLIP-003   →   do on same branch as EZCLIP-001, after build is green
EZCLIP-004   →   replace build.sh after project.yml is working
EZCLIP-005   →   separate branch, ship as v0.2
```

-----

## What the agent should NOT touch

- GRDB schema / database migrations — not reviewed, assume correct
- SwiftUI view implementations — not reviewed
- The ⌘⌘ double-tap detection logic in HotkeyMonitor — not reviewed, assumed working
- ScreenCaptureKit capture pipeline — not reviewed, assumed working
- Any business logic inside existing resolvers beyond replacing AppleScript strings

-----

*Generated by: Claude Sonnet 4.6 — acting as Technical PM*
*Based on review of: Package.swift, PRODUCT.md, README.md, v0.1.0 release notes*
*Note: Swift source files were not accessible (GitHub auth wall). EZCLIP-005 code samples are reference implementations — agent must adapt to actual existing code structure.*