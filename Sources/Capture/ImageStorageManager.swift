@preconcurrency import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ImageStorageManager: @unchecked Sendable {
    static let shared = ImageStorageManager()

    private let storageRoot: URL
    private let imageCache = NSCache<NSString, NSImage>()

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        storageRoot = appSupport.appendingPathComponent("ezclip/Screenshots")
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)

        imageCache.countLimit = 90
        imageCache.totalCostLimit = 48 * 1024 * 1024
    }

    func screenshotDir(for date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dir = storageRoot.appendingPathComponent(formatter.string(from: date))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func saveScreenshot(_ image: NSImage, captureId: UUID) throws -> (fullPath: String, thumbPath: String) {
        let dir = screenshotDir()

        let fullFile = dir.appendingPathComponent("\(captureId.uuidString).png")
        let thumbFile = dir.appendingPathComponent("\(captureId.uuidString)_thumb.png")

        // Save full resolution
        try writePNG(image, to: fullFile)

        // Save thumbnail (max 400px)
        let thumb = createThumbnail(from: image, maxDimension: 400)
        try writePNG(thumb, to: thumbFile)

        return (fullFile.path, thumbFile.path)
    }

    func saveData(_ data: Data, name: String) throws -> String {
        let dir = screenshotDir()
        let file = dir.appendingPathComponent("\(name).png")
        try data.write(to: file)
        return file.path
    }

    func fullImage(for capture: Capture) -> NSImage? {
        NSImage(contentsOfFile: capture.screenshotPath)
    }

    func thumbnailImage(for capture: Capture) -> NSImage? {
        if let thumbnail = cachedImage(path: capture.thumbnailPath, maxPixelSize: 420) {
            return thumbnail
        }
        guard let full = previewImage(for: capture, maxPixelSize: 420) else { return nil }
        return createThumbnail(from: full, maxDimension: 400)
    }

    func previewImage(for capture: Capture, maxPixelSize: CGFloat = 1400) -> NSImage? {
        cachedImage(path: capture.screenshotPath, maxPixelSize: maxPixelSize)
    }

    func faviconImage(path: String) -> NSImage? {
        cachedImage(path: path, maxPixelSize: 32)
    }

    func clearDecodedImageCache() {
        imageCache.removeAllObjects()
    }

    private func cachedImage(path: String, maxPixelSize: CGFloat) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let key = "\(path)#\(Int(maxPixelSize))" as NSString
        if let image = imageCache.object(forKey: key) {
            return image
        }

        if let image = downsampledImage(at: URL(fileURLWithPath: path), maxPixelSize: maxPixelSize) {
            imageCache.setObject(image, forKey: key, cost: estimatedCost(for: image))
            return image
        }

        if let img = NSImage(contentsOfFile: path) {
            imageCache.setObject(img, forKey: key, cost: estimatedCost(for: img))
            return img
        }

        return nil
    }

    func deleteImages(for capture: Capture) throws {
        var firstError: Error?
        let full = capture.screenshotPath
        let thumb = capture.thumbnailPath

        for path in [full, thumb, capture.faviconPath, capture.albumArtPath].compactMap({ $0 }) {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                firstError = firstError ?? error
            }
        }

        clearDecodedImageCache()

        if let firstError {
            throw firstError
        }
    }

    // MARK: - Private

    private func writePNG(_ image: NSImage, to url: URL) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw StorageError.conversionFailed
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = image.size
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw StorageError.encodingFailed
        }
        try data.write(to: url)
    }

    private func createThumbnail(from image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let scale: CGFloat
        if size.width > size.height {
            scale = min(1.0, maxDimension / size.width)
        } else {
            scale = min(1.0, maxDimension / size.height)
        }

        let thumbSize = NSSize(width: size.width * scale, height: size.height * scale)
        let thumbnail = NSImage(size: thumbSize)

        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: thumbSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()

        return thumbnail
    }

    private func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func estimatedCost(for image: NSImage) -> Int {
        let width = max(1, Int(image.size.width))
        let height = max(1, Int(image.size.height))
        return width * height * 4
    }
}

enum StorageError: LocalizedError {
    case conversionFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .conversionFailed: "Failed to convert image for storage."
        case .encodingFailed: "Failed to encode image as PNG."
        }
    }
}
