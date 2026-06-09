import Foundation

enum SessionstoreUtils {
    static func findRecoveryFile(appName: String) -> URL? {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appName)/Profiles")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: profilesDir, includingPropertiesForKeys: nil
        ) else {
            print("⚠️ \(appName): profiles dir not found at \(profilesDir.path)")
            return nil
        }

        let profile = contents.first { $0.lastPathComponent.contains(".default") }
            ?? contents.first

        guard let profile = profile else {
            print("⚠️ \(appName): no profile found in \(profilesDir.path)")
            return nil
        }

        let recovery = profile.appendingPathComponent("sessionstore-backups/recovery.jsonlz4")
        if FileManager.default.fileExists(atPath: recovery.path) { return recovery }

        let backup = profile.appendingPathComponent("sessionstore-backups/recovery.baklz4")
        if FileManager.default.fileExists(atPath: backup.path) { return backup }

        print("⚠️ \(appName): no recovery file in \(profile.path)")
        return nil
    }

    static func decompressMozLz4(at url: URL) -> [String: Any]? {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            print("⚠️ mozLz4: failed to read file: \(error)")
            return nil
        }
        guard fileData.count > 12 else {
            print("⚠️ mozLz4: file too small (\(fileData.count) bytes)")
            return nil
        }

        let expectedMagic = "mozLz40\0".data(using: .utf8)!
        guard fileData.prefix(8) == expectedMagic else {
            print("⚠️ mozLz4: bad magic: \(fileData.prefix(8).map { String(format: "%02x", $0) }.joined())")
            return nil
        }

        let uncompressedSize = Int(fileData[8..<12].withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        })
        guard uncompressedSize > 0, uncompressedSize < 50_000_000 else {
            print("⚠️ mozLz4: bad uncompressed size: \(uncompressedSize)")
            return nil
        }

        let compressed = fileData.dropFirst(12)
        print("🔍 mozLz4: decompressing \(compressed.count) → \(uncompressedSize) bytes")

        guard let decompressed = lz4Decompress(compressed, expectedSize: uncompressedSize) else {
            print("⚠️ mozLz4: lz4 decompression failed")
            return nil
        }

        do {
            let json = try JSONSerialization.jsonObject(with: decompressed) as? [String: Any]
            print("✅ mozLz4: decompressed \(decompressed.count) bytes successfully")
            return json
        } catch {
            print("⚠️ mozLz4: JSON parse failed: \(error)")
            return nil
        }
    }

    private static func lz4Decompress(_ src: Data, expectedSize: Int) -> Data? {
        var dst = Data(count: expectedSize)
        var srcIdx = src.startIndex
        var dstIdx = 0
        let srcEnd = src.endIndex

        while srcIdx < srcEnd && dstIdx < expectedSize {
            let token = Int(src[srcIdx]); srcIdx += 1
            var literalLen = token >> 4
            var matchLen = token & 0x0F

            if literalLen == 15 {
                while srcIdx < srcEnd {
                    let extra = Int(src[srcIdx]); srcIdx += 1
                    literalLen += extra
                    if extra < 255 { break }
                }
            }

            guard srcIdx + literalLen <= srcEnd else { return nil }
            if literalLen > 0 {
                dst[dstIdx..<dstIdx + literalLen] = src[srcIdx..<srcIdx + literalLen]
                srcIdx += literalLen
                dstIdx += literalLen
            }

            if dstIdx >= expectedSize { break }
            guard srcIdx + 2 <= srcEnd else { break }

            let offset = Int(src[srcIdx]) | (Int(src[srcIdx + 1]) << 8)
            srcIdx += 2
            guard offset > 0, offset <= dstIdx else { return nil }

            matchLen += 4
            if matchLen == 19 {
                while srcIdx < srcEnd {
                    let extra = Int(src[srcIdx]); srcIdx += 1
                    matchLen += extra
                    if extra < 255 { break }
                }
            }

            let matchStart = dstIdx - offset
            guard matchStart + matchLen <= expectedSize else { return nil }
            for i in 0..<matchLen {
                dst[dstIdx + i] = dst[matchStart + i]
            }
            dstIdx += matchLen
        }

        guard dstIdx == expectedSize else {
            print("⚠️ mozLz4: output size mismatch: got \(dstIdx), expected \(expectedSize)")
            return nil
        }
        return dst
    }

    static func extractActiveURL(from json: [String: Any]) -> String? {
        guard let windows = json["windows"] as? [[String: Any]] else { return nil }

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

                guard !url.hasPrefix("about:") else { continue }

                bestTime = lastAccessed
                bestURL = url
            }
        }

        return bestURL
    }
}
