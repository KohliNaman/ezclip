import Foundation
@preconcurrency import AppKit

// MARK: - Protocol

protocol AppContextResolver {
    var supportedBundleIds: [String] { get }
    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext
}

// MARK: - Result

struct ResolvedContext: Sendable {
    var contextType: ContextType
    var url: String?
    var pageTitle: String?
    var faviconData: Data?
    var songName: String?
    var artistName: String?
    var albumName: String?
    var albumArtData: Data?
    var designFileName: String?
    var designPageName: String?
    var designContext: Data?
    var filePath: String?
    var browserName: String? = nil
}

// MARK: - Engine

final class ContextResolverEngine: @unchecked Sendable {
    static let shared = ContextResolverEngine()

    private let resolvers: [AppContextResolver]

    private init() {
        resolvers = [
            SafariResolver(),
            ChromiumResolver(),
            FirefoxResolver(),
            ZenResolver(),
            SpotifyResolver(),
            AppleMusicResolver(),
            FigmaResolver(),
        ]
    }

    func resolve(bundleId: String, windowTitle: String) async -> ResolvedContext {
        var result: ResolvedContext

        // Try specific resolver first
        if let resolver = resolvers.first(where: { $0.supportedBundleIds.contains(bundleId) }) {
            do {
                result = try await resolver.resolve(windowTitle: windowTitle, bundleId: bundleId)
            } catch {
                print("⚠️ resolver failed for \(bundleId): \(error)")
                result = inferContext(appName: "", windowTitle: windowTitle, bundleId: bundleId)
            }
        } else {
            result = inferContext(appName: "", windowTitle: windowTitle, bundleId: bundleId)
        }

        // Universal fallback: if the resolver didn't find a URL but the
        // window title contains one, extract it. Covers cases where
        // AppleScript silently fails (-1728 no document, -1712 busy).
        if result.url == nil, let extracted = extractURL(from: windowTitle) {
            result.url = extracted
            if result.contextType == .generic { result.contextType = .website }
        }

        // Also try decoding percent-encoded URLs found in titles
        if result.url == nil, let decoded = percentDecode(windowTitle), let extracted = extractURL(from: decoded) {
            result.url = extracted
            if result.contextType == .generic { result.contextType = .website }
        }

        return result
    }

    /// Extracts a URL from a window title string if one is present.
    func extractURL(from text: String) -> String? {
        let decoded = percentDecode(text) ?? text
        guard let range = decoded.range(of: "https?://[^\\s.,;:!?\\)\\]\\}\\\"]+", options: .regularExpression) else {
            return nil
        }
        var url = String(decoded[range])
        let trailingPunctuation: CharacterSet = .init(charactersIn: ".,;:!?)]}\"")
        url = url.trimmingCharacters(in: trailingPunctuation)
        return url
    }

    private func percentDecode(_ text: String) -> String? {
        return text.removingPercentEncoding
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

    // MARK: - AppleScript with retry

    private nonisolated(unsafe) static var scriptStats: [String: (success: Int, failure: Int)] = [:]
    private static let statsLock = NSLock()

    func runAppleScript(_ source: String, timeout: TimeInterval = 5, label: String? = nil) -> String? {
        let maxRetries = 2
        var attempt = 0
        var lastResult: String? = nil
        var lastError: NSDictionary? = nil

        while attempt <= maxRetries {
            let script = NSAppleScript(source: source)
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            if let error = error {
                let errNum = error[NSAppleScript.errorNumber] as? Int ?? 0
                print("⚠️ AppleScript [\(errNum)]: \(error[NSAppleScript.errorMessage] ?? "unknown")")
                lastError = error
                if (errNum == -1712 || errNum == -1711) && attempt < maxRetries {
                    attempt += 1
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
                break
            }
            lastResult = result?.stringValue
            break
        }

        // Update stats
        if let label = label {
            Self.statsLock.lock()
            let current = Self.scriptStats[label] ?? (0, 0)
            if lastResult != nil {
                Self.scriptStats[label] = (current.success + 1, current.failure)
            } else {
                Self.scriptStats[label] = (current.success, current.failure + 1)
            }
            let updated = Self.scriptStats[label]!
            Self.statsLock.unlock()
            print("📊 AppleScript stats [\(label)]: success=\(updated.success), failure=\(updated.failure)")
        }

        return lastResult
    }

    func runAppleScriptAsync(_ source: String, timeout: TimeInterval = 5, label: String = "") async -> String? {
        // NSAppleScript MUST run on the main thread — dispatching to a background
        // queue causes EXC_BREAKPOINT / SIGTRAP crashes on macOS 14+.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let result = self.runAppleScript(source, timeout: timeout, label: label.isEmpty ? nil : label)
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
        return runAppleScript(script, label: "finder_path")?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
