import Foundation
import ImageIO

actor CaptureImportService {
    static let shared = CaptureImportService()

    func importFiles(_ urls: [URL]) async -> Int {
        var imported = 0
        for url in urls {
            do {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { continue }
                let id = UUID()
                let files = try await CaptureStorageActor.shared.saveScreenshot(image, captureId: id)
                if try await DatabaseManager.shared.capture(withContentHash: files.contentHash) != nil {
                    await CaptureStorageActor.shared.discard(files)
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let timestamp = values?.creationDate ?? values?.contentModificationDate ?? Date()
                let capture = Capture(
                    id: id, timestamp: timestamp, appName: "Imported", appBundleId: "com.apple.finder",
                    windowTitle: url.deletingPathExtension().lastPathComponent,
                    screenshotPath: files.fullPath, thumbnailPath: files.thumbnailPath,
                    contentHash: files.contentHash, storageStatus: "ready", contextType: .generic,
                    notes: nil, collectionId: nil, isScrolling: false, scrollIndex: nil, parentCaptureId: nil
                )
                try await CaptureRepository.shared.insert(capture)
                await LocalCaptureAnalysisService.shared.analyze(capture)
                NotificationCenter.default.post(name: .newCaptureCreated, object: capture)
                imported += 1
            } catch {
                CaptureMetrics.logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return imported
    }
}
