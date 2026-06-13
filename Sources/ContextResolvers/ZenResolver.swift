import Foundation

struct ZenResolver: AppContextResolver {
    let supportedBundleIds = ["app.zen-browser.zen", "org.mozilla.firefox"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let appSupportName = bundleId == "org.mozilla.firefox" ? "Firefox" : "zen"
        let browserName = bundleId == "org.mozilla.firefox" ? "Firefox" : "Zen"
        let pageTitle = extractPageTitle(from: windowTitle)
        let recovery = SessionstoreUtils.findRecoveryFile(appSupportName: appSupportName)
        let url = recovery
            .flatMap(SessionstoreUtils.decompressMozLz4)
            .flatMap { SessionstoreUtils.extractActiveURL(from: $0, matchingWindowTitle: windowTitle) }

        return ResolvedContext(
            contextType: .website,
            url: url ?? ContextResolverEngine.shared.extractURL(from: windowTitle),
            pageTitle: pageTitle,
            browserName: browserName
        )
    }

    private func extractPageTitle(from windowTitle: String) -> String? {
        let parts = windowTitle.components(separatedBy: " — ")
        if parts.count >= 2 {
            let title = parts.dropLast().joined(separator: " — ").trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
        return windowTitle.isEmpty ? nil : windowTitle
    }
}
