import Foundation

enum BrowserExtensionInstaller {
    static func installNativeMessagingManifests() {
        guard let bridgePath = Bundle.main.path(forAuxiliaryExecutable: "ezclip-bridge") else {
            print("⚠️ ezclip-bridge missing from app bundle")
            return
        }

        let chromiumOrigin = "chrome-extension://aneomelhkigghoclfgmpejhmpgogpfij/"
        let manifests: [(directory: String, browserFamily: String)] = [
            (
                "Library/Application Support/Google/Chrome/NativeMessagingHosts",
                "chromium"
            ),
            (
                "Library/Application Support/net.imput.helium/NativeMessagingHosts",
                "chromium"
            ),
            (
                "Library/Application Support/Mozilla/NativeMessagingHosts",
                "firefox"
            ),
            (
                "Library/Application Support/zen/NativeMessagingHosts",
                "firefox"
            )
        ]

        for manifest in manifests {
            do {
                let directory = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(manifest.directory, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var payload: [String: Any] = [
                    "name": "com.namaankohli.ezclip",
                    "description": "ezclip browser design context bridge",
                    "path": bridgePath,
                    "type": "stdio"
                ]
                if manifest.browserFamily == "chromium" {
                    payload["allowed_origins"] = [chromiumOrigin]
                } else {
                    payload["allowed_extensions"] = ["ezclip-design-context@namaankohli.com"]
                }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("com.namaankohli.ezclip.json"), options: .atomic)
            } catch {
                print("⚠️ Failed to install native messaging manifest: \(error.localizedDescription)")
            }
        }
    }
}
