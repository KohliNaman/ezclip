import Foundation

struct SafariResolver: AppContextResolver {
    let supportedBundleIds = ["com.apple.Safari"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        async let urlTask = engine.runAppleScriptAsync(
            "tell application \"Safari\" to get URL of front document",
            timeout: 5,
            label: "safari_url"
        )
        async let titleTask = engine.runAppleScriptAsync(
            "tell application \"Safari\" to get name of front document",
            timeout: 5,
            label: "safari_title"
        )

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
            faviconData: faviconData,
            browserName: "Safari"
        )
    }
}
