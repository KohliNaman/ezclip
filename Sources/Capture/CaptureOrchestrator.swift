import AppKit
import Foundation

final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private let db = DatabaseManager.shared
    private let captureManager = ScreenCaptureManager.shared
    private let contextEngine = ContextResolverEngine.shared
    private let storage = ImageStorageManager.shared
    private let scrollingManager = ScrollingCaptureManager.shared

    private init() {}

    // MARK: - Capture

    @MainActor
    func capture() async {
        do {
            // 1. Capture screenshot
            let (image, windowInfo) = try await captureManager.captureFrontmostWindow()

            // 2. Create capture ID
            let captureId = UUID()

            // 3. Save images to disk
            let (fullPath, thumbPath) = try storage.saveScreenshot(image, captureId: captureId)

            // 4. Resolve context in parallel with image saving
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

            // 6. Build Capture record
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

            // 8. Auto-tag from context
            let autoTags = deriveAutoTags(from: capture)
            if !autoTags.isEmpty {
                let tags = try await db.ensureTagsExist(autoTags)
                try await db.linkTags(tags.map(\.id), to: captureId)
            }

            // 9. Notify
            NotificationCenter.default.post(
                name: .newCaptureCreated,
                object: capture
            )

            showNotification(for: capture)

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

    @MainActor
    func captureScrolling() async {
        do {
            guard let frontApp = NSWorkspace.shared.frontmostApplication,
                  let bundleId = frontApp.bundleIdentifier else {
                return
            }

            let images = try await scrollingManager.captureScrollingPage(bundleId: bundleId)

            guard let stitched = scrollingManager.stitchImages(images) else {
                return
            }

            // Create parent capture for the stitched result
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
                faviconPath: nil,
                isScrolling: true,
                scrollIndex: nil,
                parentCaptureId: nil
            )

            try await db.write { db in
                try parent.insert(db)
            }

            // Save individual scroll slices as child captures
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

            NotificationCenter.default.post(
                name: .newCaptureCreated,
                object: parent
            )

            showNotification(for: parent)
            print("📜 Scrolling capture saved: \(images.count) slices → 1 stitched")

        } catch {
            print("❌ Scrolling capture failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Deletion

    func delete(_ capture: Capture) async throws {
        try storage.deleteImages(for: capture)
        try await db.write { db in
            // Also delete child captures if this is a scrolling parent
            if capture.isScrolling {
                let children = try Capture
                    .filter(Capture.Columns.parentCaptureId == capture.id)
                    .fetchAll(db)
                for child in children {
                    try storage.deleteImages(for: child)
                    try child.delete(db)
                }
            }
            try capture.delete(db)
        }
        NotificationCenter.default.post(
            name: .captureDeleted,
            object: capture.id
        )
    }

    // MARK: - Auto-tagging

    private func deriveAutoTags(from capture: Capture) -> [String] {
        var tags: [String] = []

        // App name
        tags.append(capture.appName.lowercased())

        // Domain from URL
        if let url = capture.url, let host = URL(string: url)?.host {
            // Strip www.
            let domain = host.replacingOccurrences(of: "www.", with: "")
            tags.append(domain)
            // Add TLD-less domain as well
            let parts = domain.components(separatedBy: ".")
            if parts.count >= 2 {
                tags.append(parts[parts.count - 2])
            }
        }

        // Artist name
        if let artist = capture.artistName {
            tags.append(artist.lowercased())
        }

        // Design file
        if let file = capture.designFileName {
            tags.append(file.lowercased())
        }

        // Context type
        tags.append(capture.contextType.rawValue)

        return Array(Set(tags))  // dedupe
    }

    // MARK: - Notifications & Alerts

    private func showNotification(for capture: Capture) {
        let notification = NSUserNotification()
        notification.identifier = capture.id.uuidString
        notification.title = "Captured!"
        notification.subtitle = capture.contextDescription
        notification.informativeText = "\(capture.appName) — \(capture.contextType.displayName)"
        notification.soundName = nil  // Silent — don't be annoying
        notification.hasActionButton = false

        // Add "Open" button
        notification.hasActionButton = true
        notification.actionButtonTitle = "Open ezclip"

        NSUserNotificationCenter.default.deliver(notification)
    }

    private func showErrorNotification(message: String) {
        let notification = NSUserNotification()
        notification.title = "Capture Failed"
        notification.informativeText = message
        NSUserNotificationCenter.default.deliver(notification)
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

// MARK: - Capture convenience initializer for scrolling

extension Capture {
    init(
        id: UUID,
        timestamp: Date,
        appName: String,
        appBundleId: String,
        windowTitle: String,
        screenshotPath: String,
        thumbnailPath: String,
        contextType: ContextType,
        url: String? = nil,
        pageTitle: String? = nil,
        faviconPath: String? = nil,
        songName: String? = nil,
        artistName: String? = nil,
        albumName: String? = nil,
        albumArtPath: String? = nil,
        designFileName: String? = nil,
        designPageName: String? = nil,
        filePath: String? = nil,
        notes: String? = nil,
        collectionId: UUID? = nil,
        isScrolling: Bool,
        scrollIndex: Int?,
        parentCaptureId: UUID?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.screenshotPath = screenshotPath
        self.thumbnailPath = thumbnailPath
        self.contextType = contextType
        self.url = url
        self.pageTitle = pageTitle
        self.faviconPath = faviconPath
        self.songName = songName
        self.artistName = artistName
        self.albumName = albumName
        self.albumArtPath = albumArtPath
        self.designFileName = designFileName
        self.designPageName = designPageName
        self.filePath = filePath
        self.notes = notes
        self.collectionId = collectionId
        self.isScrolling = isScrolling
        self.scrollIndex = scrollIndex
        self.parentCaptureId = parentCaptureId
    }
}
