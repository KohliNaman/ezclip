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
- `./Scripts/build-release.sh` creates a release archive and DMG under `build/`.
- `open ezclip.xcodeproj` opens the project for interactive development and running the app.

This repo currently has no checked-in test target. If tests are added, wire them into `project.yml` and CI.

## Coding Style & Naming Conventions

Follow idiomatic Swift style: four-space indentation, `PascalCase` for types, `camelCase` for methods/properties, and one primary type per file when practical. Name files after their main type, e.g. `CaptureOrchestrator.swift` or `LibraryViewModel.swift`. Keep UI, capture, persistence, and metadata extraction code in their existing `Sources/` subdirectories.

Prefer Swift concurrency and platform APIs already used in the codebase. Reserve comments for non-obvious platform behavior, permissions, or threading constraints.

## Testing Guidelines

Until a test target exists, validate changes with a Debug build and focused manual checks. For capture work, verify Screen Recording and Accessibility permission flows, double-Command hotkey behavior, normal window capture, and browser scrolling capture. For storage changes, verify fresh and existing databases under `~/Library/Application Support/ezclip/`.

## Commit & Pull Request Guidelines

Recent commits use concise conventional prefixes such as `feat:` and `fix:`. Keep messages imperative and specific, for example `fix: handle missing Safari URL` or `feat: add Arc favicon resolver`.

Pull requests should include a short description, user-visible behavior change, validation steps, and screenshots or screen recordings for UI changes. Call out permission, signing, entitlement, or migration impact.

## Security & Configuration Tips

Do not commit build products, signing identities, private team IDs, or user data from `~/Library/Application Support/ezclip/`. Treat `Resources/ezclip.entitlements`, `Resources/Info.plist`, `latest.json`, and release packaging changes as high-impact because they affect permissions, updates, and distribution.
