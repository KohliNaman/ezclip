@preconcurrency import AppKit
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Capture

    func capture() async {
        do {
            // 1. Capture on MainActor, convert NSImage to Data before crossing actor
            let captureData: (imageData: Data, windowInfo: WindowInfo, image: NSImage)
            captureData = try await Task { @MainActor in
                let (image, windowInfo) = try await captureManager.captureFrontmostWindow()
                // Convert to Data while on MainActor
                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmap.representation(using: .png, properties: [:]) else {
                    throw CaptureError.captureFailed
                }
                return (pngData, windowInfo, image)
            }.value

            let captureId = UUID()
            let (fullPath, thumbPath) = try storage.saveScreenshot(captureData.image, captureId: captureId)

            let context = await contextEngine.resolve(
                bundleId: captureData.windowInfo.bundleId,
                windowTitle: captureData.windowInfo.windowTitle
            )

            var faviconPath: String?
            if let favData = context.faviconData {
                faviconPath = try? storage.saveData(favData, name: "\(captureId)_favicon")
            }
            var albumArtPath: String?
            if let artData = context.albumArtData {
                albumArtPath = try? storage.saveData(artData, name: "\(captureId)_albumart")
            }

            var capture = Capture(
                id: captureId,
                timestamp: Date(),
                appName: captureData.windowInfo.appName,
                appBundleId: captureData.windowInfo.bundleId,
                windowTitle: captureData.windowInfo.windowTitle,
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

            try await db.write { db in
                try capture.insert(db)
            }

            let autoTags = deriveAutoTags(from: capture)
            if !autoTags.isEmpty {
                let tags = try await db.ensureTagsExist(autoTags)
                try await db.linkTags(tags.map({ $0.id }), to: captureId)
            }

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

            var parent = Capture(
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

                var child = Capture(
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

    // MARK: - Notifications

    @MainActor
    private func showNotification(for capture: Capture) {
        let content = UNMutableNotificationContent()
        content.title = "Captured!"
        content.subtitle = capture.contextDescription
        content.body = "\(capture.appName) — \(capture.contextType.displayName)"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: capture.id.uuidString,
            content: content,
            trigger: nil
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
