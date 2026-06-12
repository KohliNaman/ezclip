import Foundation

struct ChromiumResolver: AppContextResolver {
    let supportedBundleIds = [
        "com.google.Chrome",
        "net.imput.helium",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let browser = browserInfo(for: bundleId)

        if let appName = browser.appleScriptName {
            let (url, title) = await resolveViaAppleScript(appName: appName, label: browser.name.lowercased())
            if let url {
                return ResolvedContext(
                    contextType: .website,
                    url: url,
                    pageTitle: title ?? extractPageTitle(from: windowTitle, browserName: browser.name),
                    browserName: browser.name
                )
            }
        }

        if let profileRoot = browser.profileRoot,
           let session = ChromiumSessionReader(profileRoot: profileRoot).readMostRecentURL() {
            return ResolvedContext(
                contextType: .website,
                url: session.url,
                pageTitle: session.title ?? extractPageTitle(from: windowTitle, browserName: browser.name),
                browserName: browser.name
            )
        }

        return ResolvedContext(
            contextType: .website,
            url: ContextResolverEngine.shared.extractURL(from: windowTitle),
            pageTitle: extractPageTitle(from: windowTitle, browserName: browser.name),
            browserName: browser.name
        )
    }

    private func resolveViaAppleScript(appName: String, label: String) async -> (url: String?, title: String?) {
        let urlScript = """
        tell application "\(appName)"
            get URL of active tab of front window
        end tell
        """
        let titleScript = """
        tell application "\(appName)"
            get title of active tab of front window
        end tell
        """

        async let url = ContextResolverEngine.shared.runAppleScriptAsync(urlScript, label: "\(label)_url")
        async let title = ContextResolverEngine.shared.runAppleScriptAsync(titleScript, label: "\(label)_title")
        return await (url, title)
    }

    private func browserInfo(for bundleId: String) -> BrowserInfo {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")

        switch bundleId {
        case "com.google.Chrome":
            return BrowserInfo(name: "Chrome", appleScriptName: "Google Chrome", profileRoot: support.appendingPathComponent("Google/Chrome"))
        case "net.imput.helium":
            return BrowserInfo(name: "Helium", appleScriptName: "Helium", profileRoot: support.appendingPathComponent("net.imput.helium"))
        case "company.thebrowser.Browser":
            return BrowserInfo(name: "Arc", appleScriptName: "Arc", profileRoot: support.appendingPathComponent("Arc/User Data"))
        case "com.brave.Browser":
            return BrowserInfo(name: "Brave", appleScriptName: "Brave Browser", profileRoot: support.appendingPathComponent("BraveSoftware/Brave-Browser"))
        case "com.microsoft.edgemac":
            return BrowserInfo(name: "Edge", appleScriptName: "Microsoft Edge", profileRoot: support.appendingPathComponent("Microsoft Edge"))
        case "com.vivaldi.Vivaldi":
            return BrowserInfo(name: "Vivaldi", appleScriptName: "Vivaldi", profileRoot: support.appendingPathComponent("Vivaldi"))
        case "com.operasoftware.Opera":
            return BrowserInfo(name: "Opera", appleScriptName: "Opera", profileRoot: support.appendingPathComponent("com.operasoftware.Opera"))
        default:
            return BrowserInfo(name: "Chromium", appleScriptName: nil, profileRoot: nil)
        }
    }

    private func extractPageTitle(from windowTitle: String, browserName: String) -> String? {
        guard !windowTitle.isEmpty else { return nil }
        let suffixes = [
            " — \(browserName)", " - \(browserName)", " | \(browserName)",
            " — Google Chrome", " - Google Chrome", " — Arc", " — Helium"
        ]
        for suffix in suffixes where windowTitle.hasSuffix(suffix) {
            let title = String(windowTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
        return windowTitle
    }
}

private struct BrowserInfo {
    let name: String
    let appleScriptName: String?
    let profileRoot: URL?
}

struct ChromiumSessionReader {
    let profileRoot: URL

    func readMostRecentURL() -> (url: String, title: String?)? {
        guard let profile = findProfileDirectory() else { return nil }

        let sessionsDir = profile.appendingPathComponent("Sessions")
        if let session = readNewestSessionFile(in: sessionsDir) {
            return session
        }

        let candidates = [
            profile.appendingPathComponent("Current Session"),
            profile.appendingPathComponent("Last Session"),
            profile.appendingPathComponent("Current Tabs"),
            profile.appendingPathComponent("Last Tabs"),
        ]

        for file in candidates where FileManager.default.fileExists(atPath: file.path) {
            if let session = readURLsFromBinary(file).last {
                return session
            }
        }

        return nil
    }

    private func findProfileDirectory() -> URL? {
        let localState = profileRoot.appendingPathComponent("Local State")
        if let data = try? Data(contentsOf: localState),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let profile = json["profile"] as? [String: Any],
           let lastUsed = profile["last_used"] as? String {
            let candidate = profileRoot.appendingPathComponent(lastUsed)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let defaults = ["Default", "Profile 1", "Profile 2"].map { profileRoot.appendingPathComponent($0) }
        if let existing = defaults.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return existing
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: profileRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return nil }

        return contents.first { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
            (url.lastPathComponent == "Default" || url.lastPathComponent.hasPrefix("Profile "))
        }
    }

    private func readNewestSessionFile(in directory: URL) -> (url: String, title: String?)? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let sorted = files
            .filter { $0.lastPathComponent.hasPrefix("Tabs_") || $0.lastPathComponent.hasPrefix("Session_") }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }

        for file in sorted {
            if let session = readURLsFromBinary(file).last {
                return session
            }
        }
        return nil
    }

    private func readURLsFromBinary(_ file: URL) -> [(url: String, title: String?)] {
        guard let data = try? Data(contentsOf: file) else {
            return []
        }

        let scalars = data.map { byte -> UInt8 in
            if byte >= 32 && byte <= 126 { return byte }
            return 32
        }
        let text = String(decoding: scalars, as: UTF8.self)
        let pattern = #"https?://[^\s<>"'\)\]\}]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            let url = String(text[matchRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\""))
            guard URL(string: url)?.scheme != nil else { return nil }
            return (url, nil)
        }
    }
}
