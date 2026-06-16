@preconcurrency import AppKit
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class CapturePipeline {
    static let shared = CapturePipeline()

    private let captureManager = ScreenCaptureManager.shared
    private let contextEngine = ContextResolverEngine.shared
    private let repository = CaptureRepository.shared
    private let storage = ImageStorageManager.shared

    private init() {}

    func capture() async {
        CaptureOverlay.shared.showCapturing()

        do {
            let (image, windowInfo) = try await captureManager.captureFrontmostWindow()
            CaptureOverlay.shared.showCapturing(appName: windowInfo.appName, bundleId: windowInfo.bundleId)

            let captureId = UUID()
            let (fullPath, thumbPath) = try storage.saveScreenshot(image, captureId: captureId)

            var capture = Capture(
                id: captureId,
                timestamp: Date(),
                appName: windowInfo.appName,
                appBundleId: windowInfo.bundleId,
                windowTitle: windowInfo.windowTitle,
                screenshotPath: fullPath,
                thumbnailPath: thumbPath,
                contextType: .generic,
                notes: nil,
                collectionId: nil,
                isScrolling: false,
                scrollIndex: nil,
                parentCaptureId: nil
            )
            capture.contextStatus = "pending"

            try await repository.insert(capture)
            NotificationCenter.default.post(name: .newCaptureCreated, object: capture)
            CaptureOverlay.shared.showSaved(
                thumbnail: NSImage(contentsOfFile: thumbPath),
                appName: windowInfo.appName,
                bundleId: windowInfo.bundleId
            )

            Task { @MainActor in
                ClipboardManager.shared.copyToClipboard(image)
            }

            Task { @MainActor in
                await resolveContext(for: capture, windowInfo: windowInfo)
            }

            print("📸 Captured shell: \(windowInfo.appName) — \(windowInfo.windowTitle)")
        } catch CaptureError.permissionDenied {
            CaptureOverlay.shared.showFailed()
            print("⚠️ Screen Recording permission not granted; relying on the native macOS permission flow.")
        } catch {
            CaptureOverlay.shared.showFailed()
            print("❌ Capture failed: \(error.localizedDescription)")
            showErrorNotification(message: error.localizedDescription)
        }
    }

    private func resolveContext(for capture: Capture, windowInfo: WindowInfo) async {
        let context = await contextEngine.resolve(
            bundleId: windowInfo.bundleId,
            windowTitle: windowInfo.windowTitle
        )
        var enrichedContext = context
        if enrichedContext.contextType == .website {
            enrichedContext.designContextJSON = BrowserDesignContextStore.latestJSON(matching: enrichedContext.url)
        }

        do {
            let faviconPath = saveFaviconIfNeeded(context: enrichedContext, captureId: capture.id)
            let albumArtPath = saveAlbumArtIfNeeded(context: enrichedContext, captureId: capture.id)

            guard let updated = try await repository.updateContext(
                captureId: capture.id,
                context: enrichedContext,
                faviconPath: faviconPath,
                albumArtPath: albumArtPath
            ) else { return }

            try await repository.replaceTags(for: updated, names: Self.deriveAutoTags(from: updated))
            NotificationCenter.default.post(name: .newCaptureCreated, object: updated)
            showNotification(for: updated)
            if AITaggingSettings.current.autoTagNewCaptures {
                Task { @MainActor in
                    await AITaggingService.shared.generateTags(for: updated, isUserInitiated: false)
                }
            }
            print("🧭 Context resolved: \(updated.contextDescription)")
        } catch {
            try? await repository.markContextFailed(captureId: capture.id)
            print("⚠️ Context update failed: \(error.localizedDescription)")
        }
    }

    private func saveFaviconIfNeeded(context: ResolvedContext, captureId: UUID) -> String? {
        guard let data = context.faviconData else {
            return nil
        }
        return try? storage.saveData(data, name: "\(captureId)_favicon")
    }

    private func saveAlbumArtIfNeeded(context: ResolvedContext, captureId: UUID) -> String? {
        guard let data = context.albumArtData else { return nil }
        return try? storage.saveData(data, name: "\(captureId)_albumart")
    }

    static func deriveAutoTags(from capture: Capture) -> [String] {
        var tags: [String] = [capture.appName.lowercased()]

        if let url = capture.url, let host = URL(string: url)?.host {
            let cleanedHost = host.lowercased().replacingOccurrences(of: "www.", with: "")
            let parts = cleanedHost.components(separatedBy: ".").filter { !$0.isEmpty }
            tags.append(parts.count >= 2 ? parts[parts.count - 2] : cleanedHost)
        }
        if let artist = capture.artistName { tags.append(artist.lowercased()) }
        if let file = capture.designFileName { tags.append(file.lowercased()) }
        tags.append(capture.contextType.rawValue)

        return Array(Set(tags)).filter { !$0.isEmpty }
    }

    private func showNotification(for capture: Capture) {
        let content = UNMutableNotificationContent()
        content.title = "Captured!"
        content.subtitle = capture.contextDescription
        content.body = "\(capture.appName) - \(capture.contextType.displayName)"
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

}
