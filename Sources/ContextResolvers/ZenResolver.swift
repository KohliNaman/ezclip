import Foundation
@preconcurrency import AppKit

/// Resolves context from Zen Browser silently via sessionstore.
///
/// Reads recovery.jsonlz4 from disk, decompresses mozLz4 with a
/// pure-Swift LZ4 block decoder (no Apple Compression framework),
/// and extracts the active tab URL. The browser never knows.
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

    // MARK: - mozLz4 Decompression (Pure Swift LZ4)

    /// mozLz4: 8-byte magic "mozLz40\0" + 4-byte LE uint32 size + raw lz4 data.
    /// Uses a pure-Swift LZ4 block decompressor — no Apple Compression framework,
    /// no Python, no external tools. Reliable on Apple Silicon.
    ///
    /// The LZ4 raw block format (as produced by LZ4_compress_default):
    ///   Sequence of { token, [literals], [offset, match_length] }
    ///   Token: upper 4b = literal_len, lower 4b = match_len (pre-MINMATCH)
    ///   Extra length bytes follow when value is 255 (additive, chain stops at <255)
    ///   Match copies from already-decompressed output at (pos - offset)
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
        print("🔍 ZenResolver: lz4 decompressing \(compressed.count) → \(uncompressedSize) bytes")

        guard let decompressed = lz4Decompress(compressed, expectedSize: uncompressedSize) else {
            print("⚠️ ZenResolver: lz4 decompression failed")
            return nil
        }

        do {
            let json = try JSONSerialization.jsonObject(with: decompressed) as? [String: Any]
            print("✅ ZenResolver: lz4 decompressed \(decompressed.count) bytes successfully")
            return json
        } catch {
            print("⚠️ ZenResolver: JSON parse failed: \(error)")
            return nil
        }
    }

    /// Pure Swift LZ4 raw block decompressor. Handles the format produced by
    /// LZ4_compress_default / mozLz4 — no framing, just raw sequences.
    private func lz4Decompress(_ src: Data, expectedSize: Int) -> Data? {
        var dst = Data(count: expectedSize)
        var srcIdx = src.startIndex
        var dstIdx = 0
        let srcEnd = src.endIndex

        while srcIdx < srcEnd && dstIdx < expectedSize {
            // --- Token ---
            let token = Int(src[srcIdx]); srcIdx += 1
            var literalLen = token >> 4
            var matchLen = token & 0x0F

            // --- Literal length (extensible) ---
            if literalLen == 15 {
                while srcIdx < srcEnd {
                    let extra = Int(src[srcIdx]); srcIdx += 1
                    literalLen += extra
                    if extra < 255 { break }
                }
            }

            // --- Copy literals ---
            guard srcIdx + literalLen <= srcEnd else { return nil }
            if literalLen > 0 {
                dst[dstIdx..<dstIdx + literalLen] = src[srcIdx..<srcIdx + literalLen]
                srcIdx += literalLen
                dstIdx += literalLen
            }

            // --- Match (may be absent at end of stream) ---
            if dstIdx >= expectedSize { break }
            guard srcIdx + 2 <= srcEnd else { break }

            // Offset (little-endian 16-bit)
            let offset = Int(src[srcIdx]) | (Int(src[srcIdx + 1]) << 8)
            srcIdx += 2
            guard offset > 0, offset <= dstIdx else { return nil }

            // Match length (extensible, MINMATCH = 4)
            matchLen += 4
            if matchLen == 19 { // 15 + 4
                while srcIdx < srcEnd {
                    let extra = Int(src[srcIdx]); srcIdx += 1
                    matchLen += extra
                    if extra < 255 { break }
                }
            }

            // --- Copy match (may overlap — RLE) ---
            let matchStart = dstIdx - offset
            guard matchStart + matchLen <= expectedSize else { return nil }
            for i in 0..<matchLen {
                dst[dstIdx + i] = dst[matchStart + i]
            }
            dstIdx += matchLen
        }

        guard dstIdx == expectedSize else {
            print("⚠️ ZenResolver: lz4 output size mismatch: got \(dstIdx), expected \(expectedSize)")
            return nil
        }
        return dst
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
}
