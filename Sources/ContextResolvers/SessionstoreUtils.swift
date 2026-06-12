import Foundation

enum SessionstoreUtils {
    static func findRecoveryFile(appSupportName: String) -> URL? {
        let appSupportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(appSupportName)")
        return findRecoveryFile(appSupportURL: appSupportURL)
    }

    static func findRecoveryFile(appSupportURL: URL) -> URL? {
        let profilesDir = appSupportURL.appendingPathComponent("Profiles")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        let profilesByName = Dictionary(uniqueKeysWithValues: contents.map { ($0.lastPathComponent, $0) })
        let orderedProfiles = profilePaths(from: appSupportURL.appendingPathComponent("profiles.ini"))
            .compactMap { profilesByName[$0.lastPathComponent] ?? (FileManager.default.fileExists(atPath: $0.path) ? $0 : nil) }

        let remainingProfiles = contents.filter { profile in
            !orderedProfiles.contains { $0.standardizedFileURL == profile.standardizedFileURL }
        }

        return (orderedProfiles + remainingProfiles)
            .flatMap(recoveryCandidates)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { lhs, rhs in
                modificationDate(lhs) < modificationDate(rhs)
            }
    }

    private static func profilePaths(from profilesINI: URL) -> [URL] {
        guard let text = try? String(contentsOf: profilesINI, encoding: .utf8) else { return [] }

        var installDefault: String?
        var defaultProfile: String?
        var profiles: [(path: String, isRelative: Bool, isDefault: Bool)] = []
        var currentSection: String?
        var current: [String: String] = [:]

        func flush() {
            guard let section = currentSection else { return }
            if section.hasPrefix("Install"), current["Locked"] == "1", let path = current["Default"] {
                installDefault = path
            } else if section.hasPrefix("Profile"), let path = current["Path"] {
                let isDefault = current["Default"] == "1"
                if isDefault { defaultProfile = path }
                profiles.append((path, current["IsRelative"] != "0", isDefault))
            }
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                flush()
                currentSection = String(line.dropFirst().dropLast())
                current = [:]
            } else if let equals = line.firstIndex(of: "=") {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                current[key] = value
            }
        }
        flush()

        let appSupport = profilesINI.deletingLastPathComponent()
        var orderedPaths: [String] = []
        if let installDefault { orderedPaths.append(installDefault) }
        if let defaultProfile { orderedPaths.append(defaultProfile) }
        orderedPaths.append(contentsOf: profiles.filter(\.isDefault).map(\.path))
        orderedPaths.append(contentsOf: profiles.map(\.path))

        var seen = Set<String>()
        return orderedPaths.compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
            return appSupport.appendingPathComponent(path)
        }
    }

    private static func recoveryCandidates(for profile: URL) -> [URL] {
        [
            profile.appendingPathComponent("sessionstore-backups/recovery.jsonlz4"),
            profile.appendingPathComponent("sessionstore-backups/recovery.baklz4"),
            profile.appendingPathComponent("sessionstore-backups/previous.jsonlz4"),
            profile.appendingPathComponent("zen-sessions-backup/recovery.jsonlz4"),
            profile.appendingPathComponent("zen-sessions-backup/recovery.baklz4"),
        ]
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
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

        for window in windows {
            guard let tabs = window["tabs"] as? [[String: Any]] else { continue }
            guard let selected = window["selected"] as? Int else { continue }
            let selectedTabIndex = max(0, selected - 1)
            guard selectedTabIndex < tabs.count,
                  let url = currentURL(from: tabs[selectedTabIndex])
            else { continue }
            return url
        }

        var bestURL: String?
        var bestTime: Double = 0

        for window in windows {
            guard let tabs = window["tabs"] as? [[String: Any]] else { continue }

            for tab in tabs {
                guard let lastAccessed = tab["lastAccessed"] as? Double,
                      lastAccessed > bestTime,
                      let url = currentURL(from: tab)
                else { continue }

                bestTime = lastAccessed
                bestURL = url
            }
        }

        return bestURL
    }

    private static func currentURL(from tab: [String: Any]) -> String? {
        guard let entries = tab["entries"] as? [[String: Any]],
              let index = tab["index"] as? Int,
              index > 0,
              index <= entries.count,
              let url = entries[index - 1]["url"] as? String,
              !url.hasPrefix("about:")
        else { return nil }
        return url
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
