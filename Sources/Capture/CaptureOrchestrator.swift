import AppKit
import Foundation
import UserNotifications

final class CaptureOrchestrator: @unchecked Sendable {
    static let shared = CaptureOrchestrator()

    private let db = DatabaseManager.shared
    private let captureManager = ScreenCaptureManager.shared
    private let contextEngine = ContextResolverEngine.shared
    private let storage = ImageStorageManager.shared
    private let scrollingManager = ScrollingCaptureManager.shared

    private init() {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Capture

    func capture() async {
        do {
            // 1. Capture screenshot (MainActor since it touches AppKit)
            let (image, windowInfo) = try await MainActor.run {
                try await captureManager.captureFrontmostWindow()
            }

            // 2. Create capture ID
            let captureId = UUID()

            // 3. Save images to disk
            let (fullPath, thumbPath) = try storage.saveScreenshot(image, captureId: captureId)

            // 4. Resolve context
            let context = await contextEngine.resolve(
                bundleId: windowInfo.bundleId,
                windowTitle: windowInfo.windowTitle
            )

            // 5. Save context images (favicon, album art)
            var faviconPath: String?
            if let favData = context.faviconData {
                faviconPath = try? storage.saveData(favData, name: "\(captureId)_favicon")
            }
            var albumArtPath: String?
            if let artData = context.albumArtData {
                albumArtPath = try? storage.saveData(artData, name: "\(captureId)_albumart")
            }

            // 6. Build Capture
            let capture = Capture(
                id: captureId,
                timestamp: Date(),
                appName: windowInfo.appName,
                appBundleId: windowInfo.bundleId,
                windowTitle: windowInfo.windowTitle,
                screenshotPath: fullPath,
                thumbnailPath: thumbPath,
                contextType: context.contextType,
                url: context.url,
                pageTitle: context.pageTitle,
                faviconPath: faviconPath,
                songName: context.songName,
                artistName: context.artistName,
                albumName: context.albumName,
                albumArtPath: albumArtPath,
                designFileName: context.designFileName,
                designPageName: context.designPageName,
                filePath: context.filePath,
                notes: nil,
                collectionId: nil,
                isScrolling: false,
                scrollIndex: nil,
                parentCaptureId: nil
            )

            // 7. Save to DB
            try await db.write { db in
                try capture.insert(db)
            }

            // 8. Auto-tag
            let autoTags = deriveAutoTags(from: capture)
            if !autoTags.isEmpty {
                let tags = try await db.ensureTagsExist(autoTags)
                try await db.linkTags(tags.map(\.id), to: captureId)
            }

            // 9. Notify
            await MainActor.run {
                NotificationCenter.default.post(name: .newCaptureCreated, object: capture)
                showNotification(for: capture)
            }

            print("📸 Captured: \(capture.contextDescription)")

        } catch CaptureError.permissionDenied {
            await MainActor.run {
                showPermissionAlert(
                    title: "Screen Recording Permission Required",
                    message: "ezclip needs Screen Recording permission to capture screenshots.\n\nOpen System Settings → Privacy & Security → Screen Recording, then enable ezclip."
                )
            }
        } catch {
            print("❌ Capture failed: \(error.localizedDescription)")
            await MainActor.run {
                showErrorNotification(message: error.localizedDescription)
            }
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

            let parent = Capture(
                id: parentId,
                timestamp: Date(),
                appName: frontApp.localizedName ?? "Browser",
                appBundleId: bundleId,
                windowTitle: context.pageTitle ?? "Full Page",
                screenshotPath: fullPath,
                thumbnailPath: thumbPath,
                contextType: .website,
                url: context.url,
                pageTitle: context.pageTitle,
                isScrolling: true,
                scrollIndex: nil,
                parentCaptureId: nil
            )

            try await db.write { db in
                try parent.insert(db)
            }

            for (index, slice) in images.enumerated() {
                let childId = UUID()
                let (sliceFull, sliceThumb) = try storage.saveScreenshot(slice, captureId: childId)

                let child = Capture(
                    id: childId,
                    timestamp: Date(),
                    appName: frontApp.localizedName ?? "Browser",
                    appBundleId: bundleId,
                    windowTitle: "Scroll slice \(index + 1)",
                    screenshotPath: sliceFull,
                    thumbnailPath: sliceThumb,
                    contextType: .website,
                    url: context.url,
                    pageTitle: context.pageTitle,
                    isScrolling: true,
                    scrollIndex: index,
                    parentCaptureId: parentId
                )

                try await db.write { db in
                    try child.insert(db)
                }
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .newCaptureCreated, object: parent)
                showNotification(for: parent)
            }

            print("📜 Scrolling capture saved: \(images.count) slices")

        } catch {
            print("❌ Scrolling capture failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Deletion

    func delete(_ capture: Capture) async throws {
        try storage.deleteImages(for: capture)
        try await db.write { db in
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
        var tags: [String] = []

        tags.append(capture.appName.lowercased())

        if let url = capture.url, let host = URL(string: url)?.host {
            let domain = host.replacingOccurrences(of: "www.", with: "")
            tags.append(domain)
            let parts = domain.components(separatedBy: ".")
            if parts.count >= 2 {
                tags.append(parts[parts.count - 2])
            }
        }

        if let artist = capture.artistName {
            tags.append(artist.lowercased())
        }

        if let file = capture.designFileName {
            tags.append(file.lowercased())
        }

        tags.append(capture.contextType.rawValue)

        return Array(Set(tags))
    }

    // MARK: - Notifications (UserNotifications framework)

    @MainActor
    private func showNotification(for capture: Capture) {
        let content = UNMutableNotificationContent()
        content.title = "Captured!"
        content.subtitle = capture.contextDescription
        content.body = "\(capture.appName) — \(capture.contextType.displayName)"
        content.sound = nil  // silent

        let request = UNNotificationRequest(
            identifier: capture.id.uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("⚠️ Notification failed: \(error)")
            }
        }
    }

    @MainActor
    private func showErrorNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Capture Failed"
        content.body = message
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
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
