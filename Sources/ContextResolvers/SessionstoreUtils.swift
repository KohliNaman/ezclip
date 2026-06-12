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

    static func extractActiveURL(from json: [String: Any], matchingWindowTitle windowTitle: String? = nil) -> String? {
        guard let windows = json["windows"] as? [[String: Any]] else { return nil }

        if let windowTitle,
           let matched = selectedTabCandidates(in: windows)
            .max(by: { score($0.title, against: windowTitle) < score($1.title, against: windowTitle) }),
           score(matched.title, against: windowTitle) > 0 {
            return matched.url
        }

        if let selected = selectedTabCandidates(in: windows)
            .max(by: { $0.lastAccessed < $1.lastAccessed }) {
            return selected.url
        }

        var bestURL: String?
        var bestTime: Double = 0

        for window in windows {
            guard let tabs = window["tabs"] as? [[String: Any]] else { continue }

            for tab in tabs {
                guard let lastAccessed = tab["lastAccessed"] as? Double,
                      lastAccessed > bestTime,
                      let url = currentEntry(from: tab)?.url
                else { continue }

                bestTime = lastAccessed
                bestURL = url
            }
        }

        return bestURL
    }

    private static func selectedTabCandidates(in windows: [[String: Any]]) -> [(url: String, title: String?, lastAccessed: Double)] {
        windows.compactMap { window in
            guard let tabs = window["tabs"] as? [[String: Any]],
                  let selected = window["selected"] as? Int else { return nil }
            let selectedTabIndex = max(0, selected - 1)
            guard selectedTabIndex < tabs.count,
                  let entry = currentEntry(from: tabs[selectedTabIndex])
            else { return nil }
            let lastAccessed = tabs[selectedTabIndex]["lastAccessed"] as? Double ?? 0
            return (entry.url, entry.title, lastAccessed)
        }
    }

    private static func score(_ tabTitle: String?, against windowTitle: String) -> Int {
        guard let tabTitle else { return 0 }
        let tab = normalizedTitle(tabTitle)
        let window = normalizedTitle(windowTitle)
        guard !tab.isEmpty, !window.isEmpty else { return 0 }
        if tab == window { return 1000 }
        if window.contains(tab) { return 800 + min(tab.count, 120) }
        if tab.contains(window) { return 700 + min(window.count, 120) }

        let tabWords = Set(tab.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let windowWords = Set(window.split(separator: " ").map(String.init).filter { $0.count > 2 })
        return tabWords.intersection(windowWords).count
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: " — Zen", with: "")
            .replacingOccurrences(of: " - Zen", with: "")
            .replacingOccurrences(of: " — Mozilla Firefox", with: "")
            .replacingOccurrences(of: " - Mozilla Firefox", with: "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func currentEntry(from tab: [String: Any]) -> (url: String, title: String?)? {
        guard let entries = tab["entries"] as? [[String: Any]],
              let index = tab["index"] as? Int,
              index > 0,
              index <= entries.count,
              let url = entries[index - 1]["url"] as? String,
              !url.hasPrefix("about:")
        else { return nil }
        return (url, entries[index - 1]["title"] as? String)
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
