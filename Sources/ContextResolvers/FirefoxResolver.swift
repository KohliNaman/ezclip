import Foundation

struct FirefoxResolver: AppContextResolver {
    let supportedBundleIds = ["org.mozilla.firefox"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let pageTitle = extractPageTitle(from: windowTitle)
        let url = readSessionURL()
        print("🔍 FirefoxResolver: sessionstore url = \(url ?? "nil")")

        var faviconData: Data?
        if let url = url {
            faviconData = ContextResolverEngine.shared.fetchFavicon(from: url)
        }

        return ResolvedContext(
            contextType: .website,
            browserName: "Firefox",
            url: url,
            pageTitle: pageTitle,
            faviconData: faviconData
        )
    }

    private func extractPageTitle(from windowTitle: String) -> String? {
        let parts = windowTitle.components(separatedBy: " — ")
        if parts.count >= 2 {
            let title = parts.dropLast().joined(separator: " — ")
            return title.isEmpty ? nil : title
        }
        return windowTitle.isEmpty ? nil : windowTitle
    }

    private func readSessionURL() -> String? {
        guard let recoveryURL = SessionstoreUtils.findRecoveryFile(appName: "Firefox") else {
            print("⚠️ FirefoxResolver: no sessionstore file found")
            return nil
        }
        print("🔍 FirefoxResolver: reading \(recoveryURL.path)")
        guard let json = SessionstoreUtils.decompressMozLz4(at: recoveryURL) else {
            print("⚠️ FirefoxResolver: decompression failed")
            return nil
        }
        guard let url = SessionstoreUtils.extractActiveURL(from: json) else {
            print("⚠️ FirefoxResolver: no active URL in sessionstore")
            return nil
        }
        return url
    }
}
