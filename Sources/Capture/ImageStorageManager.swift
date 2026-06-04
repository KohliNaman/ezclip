@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

final class ImageStorageManager: @unchecked Sendable {
    static let shared = ImageStorageManager()

    private let storageRoot: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        storageRoot = appSupport.appendingPathComponent("ezclip/Screenshots")
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
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
        if let img = NSImage(contentsOfFile: capture.thumbnailPath) {
            return img
        }
        // Fallback: generate from full
        guard let full = fullImage(for: capture) else { return nil }
        return createThumbnail(from: full, maxDimension: 400)
    }

    func deleteImages(for capture: Capture) throws {
        let full = capture.screenshotPath
        let thumb = capture.thumbnailPath
        if FileManager.default.fileExists(atPath: full) {
            try FileManager.default.removeItem(atPath: full)
        }
        if FileManager.default.fileExists(atPath: thumb) {
            try FileManager.default.removeItem(atPath: thumb)
        }
        if let fav = capture.faviconPath, FileManager.default.fileExists(atPath: fav) {
            try FileManager.default.removeItem(atPath: fav)
        }
        if let art = capture.albumArtPath, FileManager.default.fileExists(atPath: art) {
            try FileManager.default.removeItem(atPath: art)
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
