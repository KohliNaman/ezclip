import Foundation
@preconcurrency import AppKit

/// Resolves context from Zen Browser (Firefox fork).
/// Zen doesn't expose an AppleScript dictionary, so we use System Events
/// to simulate Cmd+L (select address bar) → Cmd+C (copy URL) → read clipboard.
struct ZenResolver: AppContextResolver {
    let supportedBundleIds = ["app.zen-browser.zen"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        // Get page title from the window title (Zen includes it)
        // Zen window titles look like: "Page Title — Zen Browser"
        let pageTitle: String? = {
            let parts = windowTitle.components(separatedBy: " — ")
            if parts.count >= 2 {
                return parts.dropLast().joined(separator: " — ")
            }
            return windowTitle.isEmpty ? nil : windowTitle
        }()

        // Extract URL via clipboard hack (Cmd+L, Cmd+C)
        let url = await extractURL(engine: engine)

        var faviconData: Data?
        if let url = url {
            faviconData = engine.fetchFavicon(from: url)
        }

        return ResolvedContext(
            contextType: .website,
            url: url,
            pageTitle: pageTitle,
            faviconData: faviconData
        )
    }

    private func extractURL(engine: ContextResolverEngine) async -> String? {
        // Save current clipboard so we can restore it
        let oldClipboard = NSPasteboard.general.string(forType: .string)

        // Focus Zen, select address bar, copy
        let script = """
        tell application "Zen" to activate
        delay 0.15
        tell application "System Events"
            tell process "Zen"
                keystroke "l" using command down
                delay 0.1
                keystroke "c" using command down
                delay 0.1
            end tell
        end tell
        """

        _ = await engine.runAppleScriptAsync(script, timeout: 3)

        // Brief pause for clipboard to populate
        try? await Task.sleep(nanoseconds: 150_000_000)

        let url = NSPasteboard.general.string(forType: .string)

        // Restore old clipboard if it was something else
        if let old = oldClipboard, old != url {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(old, forType: .string)
        }

        // Validate it looks like a URL
        if let url = url, url.hasPrefix("http") {
            return url
        }
        return nil
    }
}
