import Foundation
@preconcurrency import AppKit

/// Resolves context from Zen Browser silently via sessionstore.
///
/// Reads recovery.jsonlz4 from disk, decompresses mozLz4 with the
/// shared pure-Swift LZ4 block decoder, and extracts the active tab URL.
struct ZenResolver: AppContextResolver {
    let supportedBundleIds = ["app.zen-browser.zen"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let pageTitle = extractPageTitle(from: windowTitle)
        let url = readSessionURL()
        print("🔍 ZenResolver: sessionstore url = \(url ?? "nil")")

        var faviconData: Data?
        if let url = url {
            faviconData = ContextResolverEngine.shared.fetchFavicon(from: url)
        }

        return ResolvedContext(
            contextType: .website,
            url: url,
            pageTitle: pageTitle,
            faviconData: faviconData,
            browserName: "Zen"
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
        guard let recoveryURL = SessionstoreUtils.findRecoveryFile(appName: "zen") else {
            print("⚠️ ZenResolver: no sessionstore file found")
            return nil
        }
        print("🔍 ZenResolver: reading \(recoveryURL.path)")
        guard let json = SessionstoreUtils.decompressMozLz4(at: recoveryURL) else {
            print("⚠️ ZenResolver: decompression failed")
            return nil
        }
        guard let url = SessionstoreUtils.extractActiveURL(from: json) else {
            print("⚠️ ZenResolver: no active URL in sessionstore")
            return nil
        }
        return url
    }
}
