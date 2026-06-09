import Foundation

struct ChromiumResolver: AppContextResolver {
    let supportedBundleIds = [
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.kagi.kagimacOS",
        "com.duckduckgo.macos.browser",
    ]

    func resolve(windowTitle: String, bundleId: String) async throws -> ResolvedContext {
        let browserName = browserName(for: bundleId)

        // Tier 1: AppleScript
        let (asURL, asTitle) = await resolveViaAppleScript(bundleId: bundleId)
        if let url = asURL {
            let pageTitle = asTitle ?? extractPageTitle(from: windowTitle)
            let faviconData = ContextResolverEngine.shared.fetchFavicon(from: url)
            return ResolvedContext(
                contextType: .website,
                url: url,
                pageTitle: pageTitle,
                faviconData: faviconData,
                browserName: browserName
            )
        }

        // Tier 2: Session files
        let (sessionURL, sessionTitle) = readSessionInfo(bundleId: bundleId)

        // Tier 3: Window title extraction
        var url = sessionURL
        var pageTitle = sessionTitle ?? asTitle ?? extractPageTitle(from: windowTitle)
        if url == nil {
            url = ContextResolverEngine.shared.extractURL(from: windowTitle)
        }

        var faviconData: Data?
        if let url = url {
            faviconData = ContextResolverEngine.shared.fetchFavicon(from: url)
        }

        return ResolvedContext(
            contextType: .website,
            url: url,
            pageTitle: pageTitle,
            faviconData: faviconData,
            browserName: browserName
        )
    }

    // MARK: - Tier 1: AppleScript

    private func resolveViaAppleScript(bundleId: String) async -> (url: String?, title: String?) {
        let appName = appleScriptAppName(for: bundleId)
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
        let labelBase = appName.replacingOccurrences(of: " ", with: "_").lowercased()
        async let urlTask = ContextResolverEngine.shared.runAppleScriptAsync(
            urlScript, timeout: 5, label: "chromium_\(labelBase)_url"
        )
        async let titleTask = ContextResolverEngine.shared.runAppleScriptAsync(
            titleScript, timeout: 5, label: "chromium_\(labelBase)_title"
        )
        let url = await urlTask
        let title = await titleTask
        return (url, title)
    }

    private func appleScriptAppName(for bundleId: String) -> String {
        switch bundleId {
        case "com.google.Chrome": return "Google Chrome"
        case "com.brave.Browser": return "Brave Browser"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "company.thebrowser.Browser": return "Arc"
        case "com.vivaldi.Vivaldi": return "Vivaldi"
        case "com.operasoftware.Opera": return "Opera"
        case "com.kagi.kagimacOS": return "Orion"
        case "com.duckduckgo.macos.browser": return "DuckDuckGo"
        default: return "Google Chrome"
        }
    }

    // MARK: - Helpers

    private func browserName(for bundleId: String) -> String {
        switch bundleId {
        case "com.google.Chrome": return "Chrome"
        case "com.brave.Browser": return "Brave"
        case "com.microsoft.edgemac": return "Edge"
        case "company.thebrowser.Browser": return "Arc"
        case "com.vivaldi.Vivaldi": return "Vivaldi"
        case "com.operasoftware.Opera": return "Opera"
        case "com.kagi.kagimacOS": return "Orion"
        case "com.duckduckgo.macos.browser": return "DuckDuckGo"
        default: return "Chromium"
        }
    }

    private func extractPageTitle(from windowTitle: String) -> String? {
        let suffixes = [" — Chrome", " — Brave", " — Edge", " — Arc", " — Vivaldi", " — Opera", " — Orion", " — DuckDuckGo"]
        for suffix in suffixes {
            if windowTitle.hasSuffix(suffix) {
                return String(windowTitle.dropLast(suffix.count))
            }
        }
        return windowTitle.isEmpty ? nil : windowTitle
    }

    private func readSessionInfo(bundleId: String) -> (url: String?, title: String?) {
        guard let profileDir = findProfileDirectory(bundleId: bundleId) else { return (nil, nil) }

        let candidates = [
            profileDir.appendingPathComponent("Current Session"),
            profileDir.appendingPathComponent("Last Session"),
            profileDir.appendingPathComponent("Current Tabs"),
            profileDir.appendingPathComponent("Last Tabs"),
        ]

        for file in candidates {
            if FileManager.default.fileExists(atPath: file.path) {
                if let (url, title) = parseSessionFile(at: file) {
                    return (url, title)
                }
            }
        }
        return (nil, nil)
    }

    private func findProfileDirectory(bundleId: String) -> URL? {
        let base: URL
        switch bundleId {
        case "com.google.Chrome":
            base = homeDir.appendingPathComponent("Library/Application Support/Google/Chrome")
        case "com.brave.Browser":
            base = homeDir.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")
        case "com.microsoft.edgemac":
            base = homeDir.appendingPathComponent("Library/Application Support/Microsoft Edge")
        case "company.thebrowser.Browser":
            base = homeDir.appendingPathComponent("Library/Application Support/Arc/User Data")
        case "com.vivaldi.Vivaldi":
            base = homeDir.appendingPathComponent("Library/Application Support/Vivaldi")
        case "com.operasoftware.Opera":
            base = homeDir.appendingPathComponent("Library/Application Support/com.operasoftware.Opera")
        case "com.kagi.kagimacOS":
            base = homeDir.appendingPathComponent("Library/Application Support/Orion")
        case "com.duckduckgo.macos.browser":
            base = homeDir.appendingPathComponent("Library/Application Support/DuckDuckGo")
        default:
            return nil
        }

        let defaultProfile = base.appendingPathComponent("Default")
        if FileManager.default.fileExists(atPath: defaultProfile.path) {
            return defaultProfile
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else {
            return nil
        }
        return contents.first { $0.hasDirectoryPath && !["Snapshots", "Crashpad"].contains($0.lastPathComponent) }
    }

    private var homeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private func parseSessionFile(at url: URL) -> (url: String?, title: String?)? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let (url, title) = extractURL(fromPlist: plist) {
            return (url, title)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let (url, title) = extractURL(fromJSON: json) {
            return (url, title)
        }

        return nil
    }

    private func extractURL(fromPlist plist: [String: Any]) -> (url: String?, title: String?)? {
        guard let sessionWindows = plist["sessionWindows"] as? [[String: Any]] else { return nil }

        var bestWindow: [String: Any]?
        var bestWindowId = -1
        for window in sessionWindows {
            if let windowId = window["windowId"] as? Int, windowId > bestWindowId {
                bestWindowId = windowId
                bestWindow = window
            }
        }

        guard let window = bestWindow,
              let tabs = window["tabs"] as? [[String: Any]] else { return nil }

        for tab in tabs {
            if let selected = tab["selected"] as? Bool, selected {
                return (tab["tabURL"] as? String, tab["tabTitle"] as? String)
            }
        }
        return (tabs.first?["tabURL"] as? String, tabs.first?["tabTitle"] as? String)
    }

    private func extractURL(fromJSON json: [String: Any]) -> (url: String?, title: String?)? {
        guard let windows = json["windows"] as? [[String: Any]] else { return nil }

        var bestWindow: [String: Any]?
        var bestWindowId = -1
        for window in windows {
            if let id = window["windowId"] as? Int, id > bestWindowId {
                bestWindowId = id
                bestWindow = window
            }
        }

        guard let window = bestWindow,
              let tabs = window["tabs"] as? [[String: Any]] else { return nil }

        for tab in tabs {
            if let selected = tab["selected"] as? Bool, selected {
                return (tab["url"] as? String, tab["title"] as? String)
            }
        }
        return (tabs.first?["url"] as? String, tabs.first?["title"] as? String)
    }
}
