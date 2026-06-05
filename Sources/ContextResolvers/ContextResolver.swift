import Foundation
@preconcurrency import AppKit

// MARK: - Protocol

protocol AppContextResolver {
    var supportedBundleIds: [String] { get }
    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext
}

// MARK: - Result

struct ResolvedContext {
    let contextType: ContextType
    var url: String?
    var pageTitle: String?
    var faviconData: Data?
    var songName: String?
    var artistName: String?
    var albumName: String?
    var albumArtData: Data?
    var designFileName: String?
    var designPageName: String?
    var filePath: String?
}

// MARK: - Engine

final class ContextResolverEngine: @unchecked Sendable {
    static let shared = ContextResolverEngine()

    private let resolvers: [AppContextResolver]

    private init() {
        resolvers = [
            SafariResolver(),
            ChromeResolver(),
            ArcResolver(),
            ZenResolver(),
            SpotifyResolver(),
            AppleMusicResolver(),
            FigmaResolver(),
        ]
    }

    func resolve(bundleId: String, windowTitle: String) async -> ResolvedContext {
        // Try specific resolver first
        if let resolver = resolvers.first(where: { $0.supportedBundleIds.contains(bundleId) }) {
            do {
                return try await resolver.resolve(windowTitle: windowTitle, bundleId: bundleId)
            } catch {
                print("⚠️ resolver failed for \(bundleId): \(error)")
            }
        }

        // Fallback: infer from heuristics
        return inferContext(appName: "", windowTitle: windowTitle, bundleId: bundleId)
    }

    private func inferContext(appName: String, windowTitle: String, bundleId: String) -> ResolvedContext {
        if windowTitle.contains("http://") || windowTitle.contains("https://") {
            return ResolvedContext(contextType: .website, url: windowTitle)
        }
        if bundleId == "com.apple.finder" {
            return ResolvedContext(
                contextType: .file,
                filePath: getFinderPath()
            )
        }
        return ResolvedContext(contextType: .generic)
    }

    // MARK: - Helpers

    func runAppleScript(_ source: String, timeout: TimeInterval = 3) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error = error {
            let errNum = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1712 = app busy (Spotify common), -1728 = no document (Safari common)
            if errNum != -1712, errNum != -1728 {
                print("⚠️ AppleScript [\(errNum)]: \(error[NSAppleScript.errorMessage] ?? "unknown")")
            }
            return nil
        }
        return result?.stringValue
    }

    func runAppleScriptAsync(_ source: String, timeout: TimeInterval = 3) async -> String? {
        // NSAppleScript MUST run on the main thread — dispatching to a background
        // queue causes EXC_BREAKPOINT / SIGTRAP crashes on macOS 14+.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let result = self.runAppleScript(source, timeout: timeout)
                continuation.resume(returning: result)
            }
        }
    }

    func fetchFavicon(from url: String) -> Data? {
        guard let siteURL = URL(string: url),
              let host = siteURL.host,
              let scheme = siteURL.scheme,
              let favURL = URL(string: "\(scheme)://\(host)/favicon.ico") else {
            return nil
        }
        return try? Data(contentsOf: favURL)
    }

    func getFinderPath() -> String? {
        let script = """
        tell application "Finder"
            if (count of windows) > 0 then
                get POSIX path of (target of front window as alias)
            end if
        end tell
        """
        return runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
