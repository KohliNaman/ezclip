import Foundation

struct ChromeResolver: AppContextResolver {
    let supportedBundleIds = ["com.google.Chrome"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        async let urlTask = engine.runAppleScriptAsync("""
            tell application "Google Chrome"
                get URL of active tab of front window
            end tell
            """)

        async let titleTask = engine.runAppleScriptAsync("""
            tell application "Google Chrome"
                get title of active tab of front window
            end tell
            """)

        let url = await urlTask
        let pageTitle = await titleTask

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
