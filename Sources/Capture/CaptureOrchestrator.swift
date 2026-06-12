@preconcurrency import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private let db = DatabaseManager.shared
    private let scrollingManager = ScrollingCaptureManager.shared
    private let storage = ImageStorageManager.shared

    private init() {
        Self.requestNotificationAuth()
    }

    private nonisolated static func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func capture() async {
        await CapturePipeline.shared.capture()
    }

    func captureScrolling() async {
        guard ExperimentalFeatures.scrollingCapture else {
            print("📜 Scrolling capture is experimental and currently disabled.")
            return
        }

        do {
            guard let frontApp = NSWorkspace.shared.frontmostApplication,
                  let bundleId = frontApp.bundleIdentifier else { return }

            let images = try await scrollingManager.captureScrollingPage(bundleId: bundleId)
            guard let stitched = scrollingManager.stitchImages(images) else { return }

            let parentId = UUID()
            let context = await ContextResolverEngine.shared.resolve(bundleId: bundleId, windowTitle: "")
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
            parent.contextStatus = "resolved"

            try await db.write { db in try parent.insert(db) }
            NotificationCenter.default.post(name: .newCaptureCreated, object: parent)
            print("📜 Scrolling capture: \(images.count) slices")
        } catch {
            print("❌ Scrolling capture failed: \(error.localizedDescription)")
        }
    }

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
}
