import Foundation
@preconcurrency import AppKit

/// Checks for updates using the GitHub Releases API.
/// No manifest files to maintain — always reflects the latest GitHub Release.
/// Compares semantic versions, downloads the DMG asset, mounts, replaces, relaunches.
///
/// No cryptographic signing — relies on HTTPS for transport integrity.
/// Matches the approach used by OpenCode Desktop and other indie macOS tools.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// GitHub repo for release tracking.
    private static let repoAPI = URL(
        string: "https://api.github.com/repos/KohliNaman/ezclip/releases/latest"
    )!

    @Published private(set) var isChecking = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var remoteVersion: String?
    @Published private(set) var remoteNotes: String?
    @Published private(set) var lastError: String?

    /// Current app version (e.g. "0.3.0-beta")
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Current build number
    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private init() {}

    // MARK: - Check

    /// Check for updates. Updates `updateAvailable`, `remoteVersion`, `remoteNotes`.
    func checkForUpdates() async {
        #if DEBUG
        print("⚠️ UpdateChecker: skipping in DEBUG build")
        return
        #endif

        guard !isChecking else { return }

        isChecking = true
        defer { isChecking = false }

        lastError = nil
        updateAvailable = false
        remoteVersion = nil
        remoteNotes = nil

        do {
            var request = URLRequest(url: Self.repoAPI, timeoutInterval: 15)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            // Optional: add a token for higher rate limits (60/hr unauthenticated → 5000/hr)
            // request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 403 {
                    lastError = "GitHub API rate limit reached. Try again later."
                } else if httpResponse.statusCode == 404 {
                    lastError = "No releases found"
                } else {
                    lastError = "Server returned \(httpResponse.statusCode)"
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                lastError = "Invalid release format"
                return
            }

            // Parse version from tag (strip leading 'v' if present)
            let remoteVersionStr = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            remoteVersion = remoteVersionStr
            remoteNotes = json["body"] as? String

            // Compare versions semantically
            guard isNewer(current: currentVersion, remote: remoteVersionStr) else {
                print("✅ ezclip is up to date (\(currentVersion))")
                return
            }

            // Verify a DMG asset exists
            guard let assets = json["assets"] as? [[String: Any]],
                  assets.contains(where: { asset in
                      let name = asset["name"] as? String ?? ""
                      return name.hasSuffix(".dmg")
                  }) else {
                lastError = "No DMG asset found in release"
                return
            }

            updateAvailable = true
            print("📦 Update available: \(remoteVersionStr)")

        } catch {
            lastError = error.localizedDescription
            print("⚠️ Update check failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Download & Install

    /// Downloads the DMG from the latest GitHub Release, mounts it,
    /// replaces the current app bundle, and relaunches.
    func downloadAndInstall() async {
        guard updateAvailable else { return }

        #if DEBUG
        print("⚠️ UpdateChecker: install skipped in DEBUG build")
        return
        #endif

        do {
            // Re-fetch release to get asset download URL
            var request = URLRequest(url: Self.repoAPI, timeoutInterval: 15)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]],
                  let dmgAsset = assets.first(where: { ($0["name"] as? String ?? "").hasSuffix(".dmg") }),
                  let downloadURLStr = dmgAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLStr) else {
                lastError = "Could not find DMG download URL"
                return
            }

            // Download DMG
            print("⬇️ Downloading update from \(downloadURLStr)...")
            let (dmgData, _) = try await URLSession.shared.data(from: downloadURL)

            let tempDir = FileManager.default.temporaryDirectory
            let dmgPath = tempDir.appendingPathComponent("ezclip-update.dmg")
            try dmgData.write(to: dmgPath)

            // Mount DMG
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

            // Find the .app bundle
            let mountedApp = mountPoint.appendingPathComponent("ezclip.app")
            guard FileManager.default.fileExists(atPath: mountedApp.path) else {
                lastError = "App bundle not found in DMG"
                return
            }

            // ── Reset TCC permissions for clean re-grant on next launch ──
            // Every ad-hoc signed build has a unique code signature hash.
            // macOS ties Accessibility/ScreenRecording perms to this hash,
            // so reinstalling breaks them. Running tccutil reset clears the
            // stale entries so the native macOS dialog appears on first boot.
            print("🔑 Resetting stale TCC permissions...")
            let tccTask = Process()
            tccTask.launchPath = "/usr/bin/tccutil"
            tccTask.arguments = ["reset", "Accessibility", "com.namaankohli.ezclip"]
            try? tccTask.run()
            tccTask.waitUntilExit()

            let tccTask2 = Process()
            tccTask2.launchPath = "/usr/bin/tccutil"
            tccTask2.arguments = ["reset", "ScreenCapture", "com.namaankohli.ezclip"]
            try? tccTask2.run()
            tccTask2.waitUntilExit()

            // Swap: move current app to temp, copy new app in place
            let currentAppURL = Bundle.main.bundleURL
            let oldAppURL = tempDir.appendingPathComponent("ezclip-old.app")
            try? FileManager.default.removeItem(at: oldAppURL)
            try FileManager.default.moveItem(at: currentAppURL, to: oldAppURL)
            try FileManager.default.copyItem(at: mountedApp, to: currentAppURL)

            // Unmount and cleanup
            let unmountTask = Process()
            unmountTask.launchPath = "/usr/bin/hdiutil"
            unmountTask.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
            try unmountTask.run()
            unmountTask.waitUntilExit()

            try? FileManager.default.removeItem(at: dmgPath)
            try? FileManager.default.removeItem(at: oldAppURL)

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

    // MARK: - Version Comparison

    /// Simple semver comparison. Strips `-beta`, `-alpha` suffixes,
    /// then compares major.minor.patch numerically.
    private func isNewer(current: String, remote: String) -> Bool {
        let curParts = current
            .components(separatedBy: CharacterSet(charactersIn: "-"))
            .first?
            .split(separator: ".")
            .compactMap { Int($0) } ?? []
        let remParts = remote
            .components(separatedBy: CharacterSet(charactersIn: "-"))
            .first?
            .split(separator: ".")
            .compactMap { Int($0) } ?? []

        let maxLen = max(curParts.count, remParts.count)
        for i in 0..<maxLen {
            let cur = i < curParts.count ? curParts[i] : 0
            let rem = i < remParts.count ? remParts[i] : 0
            if rem > cur { return true }
            if rem < cur { return false }
        }
        return false
    }
}
