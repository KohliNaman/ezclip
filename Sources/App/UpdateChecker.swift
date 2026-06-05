import Foundation
import Combine

/// Simple update checker that fetches a `latest.json` manifest from the repo.
/// Compares the remote version with the current app version. If newer,
/// downloads the DMG, mounts it, and prompts the user to install.
///
/// No cryptographic signing — relies on HTTPS (GitHub raw) for transport
/// integrity. Acceptable for a free tool; matches Zen Browser's approach.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// The manifest URL — a constant URL that CI updates on each release.
    private static let manifestURL = URL(
        string: "https://raw.githubusercontent.com/KohliNaman/ezclip/main/latest.json"
    )!

    @Published private(set) var isChecking = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var remoteVersion: String?
    @Published private(set) var remoteNotes: String?
    @Published private(set) var lastError: String?

    /// The version string of the currently running app.
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The build number of the currently running app.
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private init() {}

    /// Check for updates silently. Updates `updateAvailable`, `remoteVersion`,
    /// and `remoteNotes` when a newer version is found.
    func checkForUpdates() async {
        #if DEBUG
        print("⚠️ UpdateChecker: skipping in DEBUG build")
        return
        #endif

        guard !isChecking else { return }

        isChecking = true
        lastError = nil
        updateAvailable = false
        remoteVersion = nil

        defer { isChecking = false }

        do {
            var request = URLRequest(url: Self.manifestURL, timeoutInterval: 15)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                lastError = "Server returned non-200 status"
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remoteVersionStr = json["version"] as? String,
                  let remoteBuild = json["build"] as? String,
                  let dmgURL = json["url"] as? String else {
                lastError = "Invalid manifest format"
                return
            }

            remoteVersion = remoteVersionStr
            remoteNotes = json["notes"] as? String

            // Compare build numbers (more reliable than version strings)
            let currentBuildNum = Int(currentBuild) ?? 0
            let remoteBuildNum = Int(remoteBuild) ?? 0

            if remoteBuildNum > currentBuildNum {
                updateAvailable = true
                print("📦 Update available: \(remoteVersionStr) (build \(remoteBuild))")
            } else {
                print("✅ ezclip is up to date (\(currentVersion) build \(currentBuild))")
            }
        } catch {
            lastError = error.localizedDescription
            print("⚠️ Update check failed: \(error.localizedDescription)")
        }
    }

    /// Download and install the update. Downloads the DMG to a temp location,
    /// mounts it, replaces the current app, and relaunches.
    func downloadAndInstall() async {
        guard updateAvailable else { return }

        #if DEBUG
        print("⚠️ UpdateChecker: install skipped in DEBUG build")
        return
        #endif

        do {
            var request = URLRequest(url: Self.manifestURL, timeoutInterval: 15)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dmgURLStr = json["url"] as? String,
                  let dmgURL = URL(string: dmgURLStr) else {
                lastError = "Could not parse download URL"
                return
            }

            // Download the DMG
            print("⬇️ Downloading update from \(dmgURLStr)...")
            let (dmgData, _) = try await URLSession.shared.data(from: dmgURL)

            let tempDir = FileManager.default.temporaryDirectory
            let dmgPath = tempDir.appendingPathComponent("ezclip-update.dmg")
            try dmgData.write(to: dmgPath)

            // Mount the DMG
            let mountPoint = tempDir.appendingPathComponent("ezclip-mount")
            try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

            let mountTask = Process()
            mountTask.launchPath = "/usr/bin/hdiutil"
            mountTask.arguments = ["attach", dmgPath.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
            try mountTask.run()
            mountTask.waitUntilExit()

            guard mountTask.terminationStatus == 0 else {
                lastError = "Failed to mount DMG"
                return
            }

            // Find the .app in the mounted DMG
            let appName = "ezclip.app"
            let mountedApp = mountPoint.appendingPathComponent(appName)

            guard FileManager.default.fileExists(atPath: mountedApp.path) else {
                lastError = "App not found in DMG"
                return
            }

            // Replace the current app
            let currentAppURL = Bundle.main.bundleURL
            let trashURL = tempDir.appendingPathComponent("ezclip-old.app")

            // Move current app to trash location
            try? FileManager.default.removeItem(at: trashURL)
            try FileManager.default.moveItem(at: currentAppURL, to: trashURL)

            // Copy new app into place
            try FileManager.default.copyItem(at: mountedApp, to: currentAppURL)

            // Unmount DMG
            let unmountTask = Process()
            unmountTask.launchPath = "/usr/bin/hdiutil"
            unmountTask.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
            unmountTask.run()

            // Clean up
            try? FileManager.default.removeItem(at: dmgPath)
            try? FileManager.default.removeItem(at: trashURL)

            // Relaunch
            print("🔄 Relaunching with new version...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = [currentAppURL.path]
                try? task.run()
                NSApp.terminate(nil)
            }

        } catch {
            lastError = error.localizedDescription
            print("❌ Update install failed: \(error.localizedDescription)")
        }
    }
}
