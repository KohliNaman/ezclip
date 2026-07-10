import Foundation

struct BrowserExtensionHealth: Identifiable, Sendable {
    var id: String { target.sourceBrowser }
    var target: BrowserExtensionManifestTarget
    var nativeHostInstalled: Bool
    var bridgePathValid: Bool
    var extensionInstalled: Bool
    var lastPayloadAt: Date?
    var lastPayloadURL: String?
    var lastPayloadCounts: String?
    var status: BrowserDesignEnrichmentStatus
    var message: String
}

enum BrowserExtensionDiagnostics {
    static func allHealth() -> [BrowserExtensionHealth] {
        BrowserExtensionInstaller.manifestTargets.map { health(for: $0) }
    }

    static func health(for bundleId: String?) -> BrowserExtensionHealth {
        let source = BrowserDesignContextStore.sourceBrowser(for: bundleId)
        let target = BrowserExtensionInstaller.manifestTargets.first { $0.sourceBrowser == source }
            ?? BrowserExtensionInstaller.manifestTargets[0]
        return health(for: target)
    }

    static func health(for target: BrowserExtensionManifestTarget) -> BrowserExtensionHealth {
        let manifestURL = BrowserExtensionInstaller.manifestURL(for: target)
        let manifest = decodeJSON(at: manifestURL)
        let bridgePath = manifest?["path"] as? String
        let nativeHostInstalled = manifest != nil
        let bridgePathValid = bridgePath.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
        let extensionInstalled = isExtensionInstalled(target)
        let payload = latestPayload(for: target.sourceBrowser)

        let status: BrowserDesignEnrichmentStatus
        let message: String
        if !nativeHostInstalled || !bridgePathValid {
            status = .nativeHostMissing
            message = "\(target.displayName) native messaging host is missing or points to a missing bridge."
        } else if !extensionInstalled {
            status = .extensionMissing
            message = "\(target.displayName) extension is not installed or not discoverable."
        } else if payload.context == nil {
            status = .stalePayload
            message = "\(target.displayName) extension is installed, but no payload has been received yet."
        } else {
            status = .enriched
            message = "\(target.displayName) extension sent design context."
        }

        return BrowserExtensionHealth(
            target: target,
            nativeHostInstalled: nativeHostInstalled,
            bridgePathValid: bridgePathValid,
            extensionInstalled: extensionInstalled,
            lastPayloadAt: payload.context?.capturedAt ?? payload.context?.extractedAt ?? payload.modifiedAt,
            lastPayloadURL: payload.context?.url,
            lastPayloadCounts: payload.context.map(Self.countsText),
            status: status,
            message: message
        )
    }

    static func diagnosticsText() -> String {
        allHealth().map { health in
            [
                "\(health.target.displayName): \(health.status.displayName)",
                "nativeHostInstalled=\(health.nativeHostInstalled)",
                "bridgePathValid=\(health.bridgePathValid)",
                "extensionInstalled=\(health.extensionInstalled)",
                "lastPayloadAt=\(health.lastPayloadAt?.ISO8601Format() ?? "never")",
                "lastPayloadURL=\(health.lastPayloadURL ?? "none")",
                "message=\(health.message)"
            ].joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private static func decodeJSON(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func latestPayload(for sourceBrowser: String) -> (context: BrowserDesignContext?, modifiedAt: Date?) {
        guard let directory = BrowserDesignContextStore.recordsDirectoryURL else { return (nil, nil) }
        let candidates: [URL]
        switch sourceBrowser {
        case "chrome", "helium":
            candidates = [
                directory.appendingPathComponent("\(sourceBrowser)-latest.json"),
                directory.appendingPathComponent("chromium-latest.json")
            ]
        case "firefox", "zen":
            candidates = [
                directory.appendingPathComponent("\(sourceBrowser)-latest.json"),
                directory.appendingPathComponent("firefox-latest.json")
            ]
        default:
            candidates = [directory.appendingPathComponent("\(sourceBrowser)-latest.json")]
        }

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return (nil, nil)
        }
        let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let data = try? Data(contentsOf: url),
              let context = try? JSONDecoder.ezclip.decode(BrowserDesignContext.self, from: data) else {
            return (nil, modifiedAt)
        }
        return (context, modifiedAt)
    }

    private static func countsText(_ context: BrowserDesignContext) -> String {
        "\(context.fonts.count) fonts, \(context.colors.count) colors, \(context.cssTokens.count) tokens, \(context.buttons.count) buttons"
    }

    private static func isExtensionInstalled(_ target: BrowserExtensionManifestTarget) -> Bool {
        switch target.browserFamily {
        case "chromium":
            return chromiumExtensionInstalled(target)
        case "firefox":
            return firefoxExtensionInstalled(target)
        default:
            return false
        }
    }

    private static func chromiumExtensionInstalled(_ target: BrowserExtensionManifestTarget) -> Bool {
        guard let profileRoot = target.profileRoot else { return false }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(profileRoot)
        let candidates = [
            root.appendingPathComponent("Default/Extensions/\(target.expectedExtensionId)"),
            root.appendingPathComponent("Profile 1/Extensions/\(target.expectedExtensionId)"),
            root.appendingPathComponent("Profile 2/Extensions/\(target.expectedExtensionId)")
        ]
        return candidates.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func firefoxExtensionInstalled(_ target: BrowserExtensionManifestTarget) -> Bool {
        guard let profileRoot = target.profileRoot else { return false }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(profileRoot)
        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Profiles"),
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return false }

        for profile in profiles {
            let extensionsJSON = profile.appendingPathComponent("extensions.json")
            guard let data = try? Data(contentsOf: extensionsJSON),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addons = object["addons"] as? [[String: Any]] else { continue }
            if addons.contains(where: { addon in
                addon["id"] as? String == target.expectedExtensionId &&
                (addon["active"] as? Bool ?? false) &&
                !(addon["userDisabled"] as? Bool ?? false)
            }) {
                return true
            }
        }
        return false
    }
}
