import Foundation

struct ArcResolver: AppContextResolver {
    let supportedBundleIds = ["company.thebrowser.Browser"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        // Arc is Chromium-based — window title is usually "pageTitle — Arc"
        let pageTitle: String?
        if let dashRange = windowTitle.range(of: " — Arc") {
            pageTitle = String(windowTitle[..<dashRange.lowerBound])
        } else {
            pageTitle = windowTitle
        }

        // Arc has minimal AppleScript — try AX for URL or fall back to title parsing
        // We try accessibility API for the URL bar via generic AX inspection
        async let urlTask: String? = engine.runAppleScriptAsync("""
            tell application "Arc"
                get URL of active tab of front window
            end tell
            """)

        let url = await urlTask

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
}
