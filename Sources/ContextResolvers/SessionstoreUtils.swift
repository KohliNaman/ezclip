import Foundation

enum SessionstoreUtils {
    static func findRecoveryFile(appSupportName: String) -> URL? {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appSupportName)/Profiles")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: nil
        ) else { return nil }

        let profile = contents.first { $0.lastPathComponent.localizedCaseInsensitiveContains("default") }
            ?? contents.first

        guard let profile else { return nil }

        let candidates = [
            profile.appendingPathComponent("sessionstore-backups/recovery.jsonlz4"),
            profile.appendingPathComponent("sessionstore-backups/recovery.baklz4"),
            profile.appendingPathComponent("zen-sessions-backup/recovery.jsonlz4"),
            profile.appendingPathComponent("zen-sessions-backup/recovery.baklz4"),
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func decompressMozLz4(at url: URL) -> [String: Any]? {
        guard let fileData = try? Data(contentsOf: url), fileData.count > 12 else { return nil }

        let expectedMagic = "mozLz40\0".data(using: .utf8)!
        guard fileData.prefix(8) == expectedMagic else { return nil }

        let uncompressedSize = Int(fileData[8..<12].withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        })
        guard uncompressedSize > 0, uncompressedSize < 50_000_000 else { return nil }

        let compressed = fileData.dropFirst(12)
        guard let decompressed = lz4Decompress(compressed, expectedSize: uncompressedSize) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: decompressed) as? [String: Any]
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
                      index > 0,
                      index <= entries.count,
                      let url = entries[index - 1]["url"] as? String,
                      !url.hasPrefix("about:")
                else { continue }

                bestTime = lastAccessed
                bestURL = url
            }
        }

        return bestURL
    }

    private static func lz4Decompress(_ src: Data.SubSequence, expectedSize: Int) -> Data? {
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

            guard srcIdx + literalLen <= srcEnd, dstIdx + literalLen <= expectedSize else {
                return nil
            }

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

        return dstIdx == expectedSize ? dst : nil
    }
}
