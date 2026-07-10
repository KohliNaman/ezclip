import Foundation

struct BrowserExtensionManifestTarget: Identifiable, Sendable {
    var id: String { sourceBrowser }
    var sourceBrowser: String
    var displayName: String
    var directory: String
    var browserFamily: String
    var expectedExtensionId: String
    var profileRoot: String?
}

enum BrowserExtensionInstaller {
    static let chromiumExtensionId = "aneomelhkigghoclfgmpejhmpgogpfij"
    static let firefoxExtensionId = "ezclip-design-context@namaankohli.com"
    static let hostName = "com.namaankohli.ezclip"

    static let manifestTargets: [BrowserExtensionManifestTarget] = [
        BrowserExtensionManifestTarget(
            sourceBrowser: "chrome",
            displayName: "Chrome",
            directory: "Library/Application Support/Google/Chrome/NativeMessagingHosts",
            browserFamily: "chromium",
            expectedExtensionId: chromiumExtensionId,
            profileRoot: "Library/Application Support/Google/Chrome"
        ),
        BrowserExtensionManifestTarget(
            sourceBrowser: "helium",
            displayName: "Helium",
            directory: "Library/Application Support/net.imput.helium/NativeMessagingHosts",
            browserFamily: "chromium",
            expectedExtensionId: chromiumExtensionId,
            profileRoot: "Library/Application Support/net.imput.helium"
        ),
        BrowserExtensionManifestTarget(
            sourceBrowser: "firefox",
            displayName: "Firefox",
            directory: "Library/Application Support/Mozilla/NativeMessagingHosts",
            browserFamily: "firefox",
            expectedExtensionId: firefoxExtensionId,
            profileRoot: "Library/Application Support/Firefox"
        ),
        BrowserExtensionManifestTarget(
            sourceBrowser: "zen",
            displayName: "Zen",
            directory: "Library/Application Support/zen/NativeMessagingHosts",
            browserFamily: "firefox",
            expectedExtensionId: firefoxExtensionId,
            profileRoot: "Library/Application Support/zen"
        )
    ]

    static func installNativeMessagingManifests() {
        guard let bridgePath = Bundle.main.path(forAuxiliaryExecutable: "ezclip-bridge") else {
            print("⚠️ ezclip-bridge missing from app bundle")
            return
        }

        for manifest in manifestTargets {
            do {
                let directory = manifestDirectory(for: manifest)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let payload = manifestPayload(for: manifest, bridgePath: bridgePath)
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: manifestURL(for: manifest), options: .atomic)
            } catch {
                print("⚠️ Failed to install native messaging manifest: \(error.localizedDescription)")
            }
        }
    }

    static func manifestPayload(for manifest: BrowserExtensionManifestTarget, bridgePath: String) -> [String: Any] {
        var payload: [String: Any] = [
            "name": hostName,
            "description": "ezclip browser design context bridge",
            "path": bridgePath,
            "type": "stdio"
        ]
        if manifest.browserFamily == "chromium" {
            payload["allowed_origins"] = ["chrome-extension://\(manifest.expectedExtensionId)/"]
        } else {
            payload["allowed_extensions"] = [manifest.expectedExtensionId]
        }
        return payload
    }

    static func manifestURL(for manifest: BrowserExtensionManifestTarget) -> URL {
        manifestDirectory(for: manifest).appendingPathComponent("\(hostName).json")
    }

    static func manifestDirectory(for manifest: BrowserExtensionManifestTarget) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(manifest.directory, isDirectory: true)
    }
}
