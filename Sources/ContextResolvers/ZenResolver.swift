import Foundation
import Compression
@preconcurrency import AppKit

/// Resolves context from Zen Browser. Two-stage approach:
///
/// 1. Sessionstore (silent, fast): reads recovery.jsonlz4 from disk,
///    decompresses mozLz4, extracts active tab URL. Browser never knows.
/// 2. Keyboard shortcut (fallback): if sessionstore fails, uses
///    System Events to Cmd+L → Cmd+C → read clipboard. Brief flicker
///    but guaranteed to work.
///
/// The Apple Compression framework's COMPRESSION_LZ4_RAW has known
/// compatibility issues with mozLz4 on Apple Silicon macOS 14+,
/// so we try both RAW and framed modes, plus an exact-buffer variant.
struct ZenResolver: AppContextResolver {
    let supportedBundleIds = ["app.zen-browser.zen"]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let pageTitle = extractPageTitle(from: windowTitle)

        // Stage 1: try silent sessionstore read
        var url = readSessionURL()
        print("🔍 ZenResolver: sessionstore url = \(url ?? "nil")")

        // Stage 2: fall back to keyboard shortcut (Cmd+L, Cmd+C)
        if url == nil {
            url = await extractURLViaClipboard()
            print("🔍 ZenResolver: clipboard url = \(url ?? "nil")")
        }

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
            print("⚠️ ZenResolver: no sessionstore file found")
            return nil
        }
        print("🔍 ZenResolver: reading \(recoveryURL.path)")

        guard let json = decompressMozLz4(at: recoveryURL) else {
            print("⚠️ ZenResolver: decompression failed")
            return nil
        }

        guard let url = extractActiveURL(from: json) else {
            print("⚠️ ZenResolver: no active URL in sessionstore")
            return nil
        }

        return url
    }

    private func findRecoveryFile() -> URL? {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/zen/Profiles")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: profilesDir, includingPropertiesForKeys: nil
        ) else {
            print("⚠️ ZenResolver: profiles dir not found at \(profilesDir.path)")
            return nil
        }

        let profile = contents.first { $0.lastPathComponent.contains(".default") }
            ?? contents.first

        guard let profile = profile else {
            print("⚠️ ZenResolver: no profile found in \(profilesDir.path)")
            return nil
        }

        let recovery = profile.appendingPathComponent("sessionstore-backups/recovery.jsonlz4")
        if FileManager.default.fileExists(atPath: recovery.path) { return recovery }

        let backup = profile.appendingPathComponent("sessionstore-backups/recovery.baklz4")
        if FileManager.default.fileExists(atPath: backup.path) { return backup }

        print("⚠️ ZenResolver: no recovery file in \(profile.path)")
        return nil
    }

    // MARK: - mozLz4 Decompression

    /// mozLz4: 8-byte magic "mozLz40\0" + 4-byte LE uint32 size + raw lz4 data.
    /// Tries multiple decompression strategies because Apple's Compression
    /// framework has known quirks with lz4 on Apple Silicon.
    private func decompressMozLz4(at url: URL) -> [String: Any]? {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            print("⚠️ ZenResolver: failed to read file: \(error)")
            return nil
        }
        guard fileData.count > 12 else {
            print("⚠️ ZenResolver: file too small (\(fileData.count) bytes)")
            return nil
        }

        let expectedMagic = "mozLz40\0".data(using: .utf8)!
        guard fileData.prefix(8) == expectedMagic else {
            print("⚠️ ZenResolver: bad magic: \(fileData.prefix(8).map { String(format: "%02x", $0) }.joined())")
            return nil
        }

        let uncompressedSize = Int(fileData[8..<12].withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        })
        guard uncompressedSize > 0, uncompressedSize < 50_000_000 else {
            print("⚠️ ZenResolver: bad uncompressed size: \(uncompressedSize)")
            return nil
        }

        let compressed = fileData.dropFirst(12)
        print("🔍 ZenResolver: decompressing \(compressed.count) → \(uncompressedSize) bytes")

        // Strategy 1: COMPRESSION_LZ4_RAW with exact buffer
        if let result = tryDecompress(compressed, uncompressedSize, COMPRESSION_LZ4_RAW) {
            return result
        }

        // Strategy 2: COMPRESSION_LZ4_RAW with slightly larger buffer
        if let result = tryDecompress(compressed, uncompressedSize, COMPRESSION_LZ4_RAW, extraBytes: 4096) {
            return result
        }

        // Strategy 3: COMPRESSION_LZ4 (framed) with exact buffer
        if let result = tryDecompress(compressed, uncompressedSize, COMPRESSION_LZ4) {
            return result
        }

        print("⚠️ ZenResolver: all decompression strategies failed")
        return nil
    }

    private func tryDecompress(
        _ compressed: Data,
        _ expectedSize: Int,
        _ algorithm: compression_algorithm,
        extraBytes: Int = 0
    ) -> [String: Any]? {
        let bufSize = expectedSize + extraBytes
        var decompressed = Data(count: bufSize)
        let actualSize = decompressed.withUnsafeMutableBytes { dest in
            compressed.withUnsafeBytes { src in
                compression_decode_buffer(
                    dest.baseAddress!, dest.count,
                    src.baseAddress!, src.count,
                    nil,
                    algorithm
                )
            }
        }

        guard actualSize == expectedSize else {
            print("⚠️ ZenResolver: lz4[\(algorithm)] size mismatch: got \(actualSize), expected \(expectedSize)")
            return nil
        }

        let jsonData = decompressed.prefix(actualSize)
        do {
            return try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        } catch {
            print("⚠️ ZenResolver: JSON parse failed: \(error)")
            return nil
        }
    }

    // MARK: - URL Extraction

    private func extractActiveURL(from json: [String: Any]) -> String? {
        guard let windows = json["windows"] as? [[String: Any]] else { return nil }

        var bestURL: String?
        var bestTime: Double = 0

        for (wi, window) in windows.enumerated() {
            guard let tabs = window["tabs"] as? [[String: Any]] else { continue }

            for (ti, tab) in tabs.enumerated() {
                guard let lastAccessed = tab["lastAccessed"] as? Double,
                      lastAccessed > bestTime,
                      let entries = tab["entries"] as? [[String: Any]],
                      let index = tab["index"] as? Int,
                      index > 0, index <= entries.count,
                      let url = entries[index - 1]["url"] as? String
                else { continue }

                guard !url.hasPrefix("about:") else { continue }

                bestTime = lastAccessed
                bestURL = url
            }
        }

        return bestURL
    }

    // MARK: - Keyboard Shortcut Fallback

    /// Uses System Events to press Cmd+L (select address bar) then Cmd+C
    /// (copy URL) in Zen. This briefly brings Zen to the foreground,
    /// but is guaranteed to work when sessionstore fails.
    private func extractURLViaClipboard() async -> String? {
        let oldClipboard = NSPasteboard.general.string(forType: .string)

        let script = """
        tell application "Zen" to activate
        delay 0.15
        tell application "System Events"
            tell process "Zen"
                keystroke "l" using command down
                delay 0.1
                keystroke "c" using command down
                delay 0.1
            end tell
        end tell
        """

        _ = await ContextResolverEngine.shared.runAppleScriptAsync(script, timeout: 3)
        try? await Task.sleep(nanoseconds: 150_000_000)

        let url = NSPasteboard.general.string(forType: .string)

        // Restore old clipboard
        if let old = oldClipboard, old != url {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(old, forType: .string)
        }

        if let url = url, (url.hasPrefix("http://") || url.hasPrefix("https://")) {
            return url
        }
        return nil
    }
}
