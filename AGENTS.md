# Repository Guidelines

## Project Structure & Module Organization

ezclip is a macOS Swift 6 + SwiftUI app generated from `project.yml` with XcodeGen. Main code lives in `Sources/`:

- `Sources/App/` contains app startup, delegate wiring, and update checks.
- `Sources/Capture/` contains hotkey handling, capture orchestration, scrolling capture, and image persistence.
- `Sources/ContextResolvers/` contains per-app metadata resolvers for browsers, music apps, and Figma.
- `Sources/Storage/` contains GRDB database setup and model types.
- `Sources/UI/` contains SwiftUI views and view models.

Resources are in `Resources/`, release scripts in `Scripts/`, docs in `PRODUCT.md` and `docs/specs/`, and CI in `.github/workflows/`.

## Build, Test, and Development Commands

- `xcodegen generate` regenerates `ezclip.xcodeproj` from `project.yml`.
- `xcodebuild build -project ezclip.xcodeproj -scheme ezclip -configuration Debug -destination "platform=macOS"` builds the app locally.
- `xcodebuild test -project ezclip.xcodeproj -scheme ezclip -destination "platform=macOS,arch=arm64"` runs Swift unit tests.
- `node --test BrowserExtensions/tests/extractor.test.js` runs browser extension extractor tests.
- `./Scripts/build-dev.sh` builds, installs, and opens a local Debug app in `/Applications/ezclip.app`.
- `./Scripts/build-release.sh` creates a release archive and DMG under `build/`.
- `open ezclip.xcodeproj` opens the project for interactive development and running the app.

CI runs both Swift tests and browser extension JavaScript tests.

## Coding Style & Naming Conventions

Follow idiomatic Swift style: four-space indentation, `PascalCase` for types, `camelCase` for methods/properties, and one primary type per file when practical. Name files after their main type, e.g. `CaptureOrchestrator.swift` or `LibraryViewModel.swift`. Keep UI, capture, persistence, and metadata extraction code in their existing `Sources/` subdirectories.

Prefer Swift concurrency and platform APIs already used in the codebase. Reserve comments for non-obvious platform behavior, permissions, or threading constraints.

## Testing Guidelines

Swift tests live in `Tests/` and use XCTest. Browser extension extractor tests live in `BrowserExtensions/tests/` and use Node's built-in test runner. Add fixture-driven tests for resolver parsing, sessionstore parsing, storage updates, and design-context extraction. For capture work, still verify Screen Recording and Accessibility permission flows, double-Command hotkey behavior, normal window capture, and browser design enrichment manually. For storage changes, verify fresh and existing databases under `~/Library/Application Support/ezclip/`.

## Commit & Pull Request Guidelines

Recent commits use concise conventional prefixes such as `feat:` and `fix:`. Keep messages imperative and specific, for example `fix: handle missing Safari URL` or `feat: add Arc favicon resolver`.

Pull requests should include a short description, user-visible behavior change, validation steps, and screenshots or screen recordings for UI changes. Call out permission, signing, entitlement, or migration impact.

## Security & Configuration Tips

Do not commit build products, signing identities, private team IDs, or user data from `~/Library/Application Support/ezclip/`. Treat `Resources/ezclip.entitlements`, `Resources/Info.plist`, browser extension manifests, native messaging manifests, and release packaging changes as high-impact because they affect permissions, extension connectivity, updates, and distribution.
