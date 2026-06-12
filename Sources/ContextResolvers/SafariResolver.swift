import Foundation

struct SafariResolver: AppContextResolver {
    let supportedBundleIds = ["com.apple.Safari"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let engine = ContextResolverEngine.shared

        async let urlTask = engine.runAppleScriptAsync(
            "tell application \"Safari\" to get URL of front document",
            label: "safari_url"
        )
        async let titleTask = engine.runAppleScriptAsync(
            "tell application \"Safari\" to get name of front document",
            label: "safari_title"
        )

        let url = await urlTask
        let pageTitle = await titleTask ?? (windowTitle.isEmpty ? nil : windowTitle)

        return ResolvedContext(
            contextType: .website,
            url: url,
            pageTitle: pageTitle,
            browserName: "Safari"
        )
    }
}
