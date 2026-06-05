import Foundation
import Compression

/// Resolves context from Zen Browser (Firefox fork) — silently, without
/// bringing Zen to the foreground. Reads the sessionstore recovery file
/// (mozLz4-compressed JSON) from disk and extracts the active tab URL.
///
/// Zen/Firefox continuously saves tab state to `recovery.jsonlz4` every ~15s.
/// We parse this file to get the most recently accessed tab's URL — the browser
/// never knows we're looking. No extensions, no keystrokes, no window activation.
struct ZenResolver: AppContextResolver {
    let supportedBundleIds = ["app.zen-browser.zen"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let pageTitle = extractPageTitle(from: windowTitle)

        // Read URL from sessionstore (disk-based, completely silent)
        let url = readSessionURL()

        // Sessionstore might be up to ~15s stale. If we got nothing,
        // the sessionstore file may not exist yet — that's OK, we
        // still have a valid capture with page title.
        var faviconData: Data?
        if let url = url {
            faviconData = ContextResolverEngine.shared.fetchFavicon(from: url)
        }

        return ResolvedContext(
            contextType: .website,
            url: url,
            pageTitle: pageTitle,
            faviconData: faviconData
        )
    }

    // MARK: - Page Title

    private func extractPageTitle(from windowTitle: String) -> String? {
        // Zen window titles: "Page Title — Zen Browser"
        let parts = windowTitle.components(separatedBy: " — ")
        if parts.count >= 2 {
            let title = parts.dropLast().joined(separator: " — ")
            return title.isEmpty ? nil : title
        }
        return windowTitle.isEmpty ? nil : windowTitle
    }

    // MARK: - Sessionstore

    private func readSessionURL() -> String? {
        guard let recoveryURL = findRecoveryFile() else {
            print("⚠️ ZenResolver: no sessionstore found")
            return nil
        }

        guard let json = decompressMozLz4(at: recoveryURL) else {
            print("⚠️ ZenResolver: failed to decompress sessionstore")
            return nil
        }

        guard let url = extractActiveURL(from: json) else {
            print("⚠️ ZenResolver: no active tab URL in sessionstore")
            return nil
        }

        return url
    }

    /// Locates the Zen profile's recovery file.
    /// Prefers `.default-release` profile, falls back to any profile.
    /// Tries `recovery.jsonlz4` first, then `recovery.baklz4`.
    private func findRecoveryFile() -> URL? {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/zen/Profiles")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        // Prefer the default-release profile
        let profile = contents.first { $0.lastPathComponent.contains(".default") }
            ?? contents.first

        guard let profile = profile else { return nil }

        // Try primary first, then backup
        let recovery = profile.appendingPathComponent("sessionstore-backups/recovery.jsonlz4")
        let backup = profile.appendingPathComponent("sessionstore-backups/recovery.baklz4")

        if FileManager.default.fileExists(atPath: recovery.path) { return recovery }
        if FileManager.default.fileExists(atPath: backup.path) { return backup }
        return nil
    }

    // MARK: - mozLz4 Decompression

    /// mozLz4 format:
    ///   Bytes 0-7:   magic "mozLz40\0"
    ///   Bytes 8-11:  uncompressed size (uint32, little-endian)
    ///   Bytes 12+:   raw lz4-compressed JSON
    ///
    /// Uses Apple's Compression framework for hardware-accelerated lz4 decode.
    private func decompressMozLz4(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), data.count > 12 else {
            return nil
        }

        // Verify magic header
        let expectedMagic = "mozLz40\0".data(using: .utf8)!
        guard data.prefix(8) == expectedMagic else {
            print("⚠️ ZenResolver: invalid mozLz4 magic")
            return nil
        }

        // Read uncompressed size (little-endian uint32)
        let uncompressedSize = Int(data[8..<12].withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        })

        guard uncompressedSize > 0, uncompressedSize < 50_000_000 else {
            print("⚠️ ZenResolver: unreasonable uncompressed size: \(uncompressedSize)")
            return nil
        }

        let compressed = data.dropFirst(12)

        // Decompress with lz4 raw (single-block format that Mozilla uses)
        // We allocate a bit extra — compression_decode_buffer fills only
        // what it needs and returns the actual decoded byte count.
        var decompressed = Data(count: uncompressedSize + 4096)
        let actualSize = decompressed.withUnsafeMutableBytes { dest in
            compressed.withUnsafeBytes { src in
                compression_decode_buffer(
                    dest.baseAddress!, dest.count,
                    src.baseAddress!, src.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }

        guard actualSize == uncompressedSize else {
            print("⚠️ ZenResolver: lz4 decode mismatch (got \(actualSize), expected \(uncompressedSize))")
            return nil
        }

        let jsonData = decompressed.prefix(actualSize)

        do {
            return try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        } catch {
            print("⚠️ ZenResolver: JSON parse error: \(error)")
            return nil
        }
    }

    // MARK: - URL Extraction

    /// Scans all windows and tabs to find the most recently accessed tab.
    /// Returns its URL. Skips about:blank and internal pages.
    private func extractActiveURL(from json: [String: Any]) -> String? {
        guard let windows = json["windows"] as? [[String: Any]] else {
            return nil
        }

        var bestURL: String?
        var bestTime: Double = 0

        for window in windows {
            guard let tabs = window["tabs"] as? [[String: Any]] else { continue }

            for tab in tabs {
                guard let lastAccessed = tab["lastAccessed"] as? Double,
                      lastAccessed > bestTime,
                      let entries = tab["entries"] as? [[String: Any]],
                      let index = tab["index"] as? Int,
                      index > 0, index <= entries.count,
                      let url = entries[index - 1]["url"] as? String
                else { continue }

                // Skip internal pages
                guard !url.hasPrefix("about:") else { continue }

                bestTime = lastAccessed
                bestURL = url
            }
        }

        return bestURL
    }
}
