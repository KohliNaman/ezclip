@preconcurrency import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private let db = DatabaseManager.shared
    private let captureManager = ScreenCaptureManager.shared
    private let contextEngine = ContextResolverEngine.shared
    private let storage = ImageStorageManager.shared
    private let scrollingManager = ScrollingCaptureManager.shared

    private init() {
        // Delegate to a nonisolated static method so the
        // UNUserNotificationCenter callback doesn't inherit
        // @MainActor isolation. The callback fires on an arbitrary
        // XPC queue; inheriting MainActor causes a runtime trap.
        Self.requestNotificationAuth()
    }

    private nonisolated static func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Capture

    func capture() async {
        do {
            let (image, windowInfo) = try await captureManager.captureFrontmostWindow()

            let captureId = UUID()
            let (fullPath, thumbPath) = try storage.saveScreenshot(image, captureId: captureId)

            // Notify the browser extension and wait for design context
            LocalCaptureServer.shared.setPending(requestId: captureId)
            defer { LocalCaptureServer.shared.clearPending() }

            async let extensionContext = LocalCaptureServer.shared.waitForContext(timeout: 3)

            // Copy to clipboard with 10-minute auto-expiry
            ClipboardManager.shared.copyToClipboard(image)

            let context = await contextEngine.resolve(
                bundleId: windowInfo.bundleId,
                windowTitle: windowInfo.windowTitle
            )

            var mergedContext = context
            if let extData = await extensionContext {
                mergedContext.designContext = extData
            }

            var faviconPath: String?
            if let favData = mergedContext.faviconData {
                faviconPath = try? storage.saveData(favData, name: "\(captureId)_favicon")
            }
            var albumArtPath: String?
            if let artData = mergedContext.albumArtData {
                albumArtPath = try? storage.saveData(artData, name: "\(captureId)_albumart")
            }

            let designContextJSON: String? = mergedContext.designContext.flatMap {
                guard let data = try? JSONSerialization.data(withJSONObject: $0) else { return nil }
                return String(data: data, encoding: .utf8)
            }

            var capture = Capture(
                id: captureId,
                timestamp: Date(),
                appName: windowInfo.appName,
                appBundleId: windowInfo.bundleId,
                windowTitle: windowInfo.windowTitle,
                screenshotPath: fullPath,
                thumbnailPath: thumbPath,
                contextType: mergedContext.contextType,
                url: mergedContext.url,
                pageTitle: mergedContext.pageTitle,
                faviconPath: faviconPath,
                songName: mergedContext.songName,
                artistName: mergedContext.artistName,
                albumName: mergedContext.albumName,
                albumArtPath: albumArtPath,
                designFileName: mergedContext.designFileName,
                designPageName: mergedContext.designPageName,
                designContextJSON: designContextJSON,
                filePath: mergedContext.filePath,
                notes: nil,
                collectionId: nil,
                isScrolling: false,
                scrollIndex: nil,
                parentCaptureId: nil
            )

            try await db.write { db in try capture.insert(db) }

            let autoTags = deriveAutoTags(from: capture)
            if !autoTags.isEmpty {
                let tags = try await db.ensureTagsExist(autoTags)
                try await db.linkTags(tags.map({ $0.id }), to: captureId)
            }

            NotificationCenter.default.post(name: .newCaptureCreated, object: capture)
            showNotification(for: capture)
            let thumb = NSImage(contentsOfFile: thumbPath)
            CaptureOverlay.shared.show(context: mergedContext, thumbnail: thumb, appName: windowInfo.appName, bundleId: windowInfo.bundleId)

            print("📸 Captured: \(capture.contextDescription)")

        } catch CaptureError.permissionDenied {
            showPermissionAlert(
                title: "Screen Recording Permission Required",
                message: "ezclip needs Screen Recording permission to capture screenshots.\n\nOpen System Settings → Privacy & Security → Screen Recording, then enable ezclip."
            )
        } catch {
            print("❌ Capture failed: \(error.localizedDescription)")
            showErrorNotification(message: error.localizedDescription)
        }
    }

    // MARK: - Scrolling Capture

    func captureScrolling() async {
        do {
            guard let frontApp = NSWorkspace.shared.frontmostApplication,
                  let bundleId = frontApp.bundleIdentifier else { return }

            let images = try await scrollingManager.captureScrollingPage(bundleId: bundleId)
            guard let stitched = scrollingManager.stitchImages(images) else { return }

            let parentId = UUID()
            let context = await contextEngine.resolve(bundleId: bundleId, windowTitle: "")
            let (fullPath, thumbPath) = try storage.saveScreenshot(stitched, captureId: parentId)

            var parent = Capture(
                id: parentId, timestamp: Date(),
                appName: frontApp.localizedName ?? "Browser",
                appBundleId: bundleId,
                windowTitle: context.pageTitle ?? "Full Page",
                screenshotPath: fullPath, thumbnailPath: thumbPath,
                contextType: .website, url: context.url, pageTitle: context.pageTitle,
                isScrolling: true, scrollIndex: nil, parentCaptureId: nil
            )

            try await db.write { db in try parent.insert(db) }

            for (index, slice) in images.enumerated() {
                let childId = UUID()
                let (sliceFull, sliceThumb) = try storage.saveScreenshot(slice, captureId: childId)
                var child = Capture(
                    id: childId, timestamp: Date(),
                    appName: frontApp.localizedName ?? "Browser",
                    appBundleId: bundleId,
                    windowTitle: "Scroll slice \(index + 1)",
                    screenshotPath: sliceFull, thumbnailPath: sliceThumb,
                    contextType: .website, url: context.url, pageTitle: context.pageTitle,
                    isScrolling: true, scrollIndex: index, parentCaptureId: parentId
                )
                try await db.write { db in try child.insert(db) }
            }

            NotificationCenter.default.post(name: .newCaptureCreated, object: parent)
            showNotification(for: parent)
            print("📜 Scrolling capture: \(images.count) slices")

        } catch {
            print("❌ Scrolling capture failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Deletion

    func delete(_ capture: Capture) async throws {
        try storage.deleteImages(for: capture)
        try await db.write { [self] db in
            if capture.isScrolling {
                let children = try Capture
                    .filter(sql: "parentCaptureId = ?", arguments: [capture.id.uuidString])
                    .fetchAll(db)
                for child in children {
                    try storage.deleteImages(for: child)
                    try child.delete(db)
                }
            }
            try capture.delete(db)
        }
        NotificationCenter.default.post(name: .captureDeleted, object: capture.id)
    }

    // MARK: - Auto-tagging

    private func deriveAutoTags(from capture: Capture) -> [String] {
        var tags: [String] = [capture.appName.lowercased()]

        if let url = capture.url, let host = URL(string: url)?.host {
            tags.append(host.replacingOccurrences(of: "www.", with: ""))
            let parts = host.components(separatedBy: ".")
            if parts.count >= 2 { tags.append(parts[parts.count - 2]) }
        }
        if let artist = capture.artistName { tags.append(artist.lowercased()) }
        if let file = capture.designFileName { tags.append(file.lowercased()) }
        tags.append(capture.contextType.rawValue)

        return Array(Set(tags))
    }

    // MARK: - Notifications

    private func showNotification(for capture: Capture) {
        let content = UNMutableNotificationContent()
        content.title = "Captured!"
        content.subtitle = capture.contextDescription
        content.body = "\(capture.appName) — \(capture.contextType.displayName)"
        content.sound = nil
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: capture.id.uuidString, content: content, trigger: nil)
        )
    }

    private func showErrorNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Capture Failed"
        content.body = message
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func showPermissionAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            )
        }
    }
}
