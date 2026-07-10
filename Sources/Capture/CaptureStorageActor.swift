@preconcurrency import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StoredCaptureFiles: Sendable {
    var fullPath: String
    var thumbnailPath: String
    var contentHash: String
}

actor CaptureStorageActor {
    static let shared = CaptureStorageActor()

    private let root: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = appSupport.appendingPathComponent("ezclip/Screenshots", isDirectory: true)
    }

    func saveScreenshot(_ image: CGImage, captureId: UUID, timestamp: Date = Date()) throws -> StoredCaptureFiles {
        let directory = try directory(for: timestamp)
        let fullURL = directory.appendingPathComponent("\(captureId.uuidString).png")
        let thumbnailURL = directory.appendingPathComponent("\(captureId.uuidString)_thumb.jpg")

        let png = try encodedData(image, type: .png, properties: [:])
        guard let thumbnail = downsample(image, maxPixelSize: 600) else {
            throw StorageError.conversionFailed
        }
        let jpeg = try encodedData(
            thumbnail,
            type: .jpeg,
            properties: [kCGImageDestinationLossyCompressionQuality: 0.78]
        )

        do {
            try atomicWrite(png, to: fullURL)
            try atomicWrite(jpeg, to: thumbnailURL)
        } catch {
            try? FileManager.default.removeItem(at: fullURL)
            try? FileManager.default.removeItem(at: thumbnailURL)
            throw error
        }

        return StoredCaptureFiles(
            fullPath: fullURL.path,
            thumbnailPath: thumbnailURL.path,
            contentHash: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        )
    }

    func drainDeletionQueue() async {
        guard let records = try? await DatabaseManager.shared.pendingFileDeletions(limit: 100) else { return }
        for record in records {
            do {
                if FileManager.default.fileExists(atPath: record.path) {
                    try FileManager.default.removeItem(atPath: record.path)
                }
                try await DatabaseManager.shared.completeFileDeletion(id: record.id)
            } catch {
                try? await DatabaseManager.shared.failFileDeletion(id: record.id, error: error.localizedDescription)
            }
        }
        ImageStorageManager.shared.clearDecodedImageCache()
    }

    func discard(_ files: StoredCaptureFiles) {
        try? FileManager.default.removeItem(atPath: files.fullPath)
        try? FileManager.default.removeItem(atPath: files.thumbnailPath)
    }

    func removeAbandonedTemporaryFiles() {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for case let url as URL in enumerator where url.pathExtension == "tmp" {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if (modified ?? .distantPast) < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func directory(for date: Date) throws -> URL {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let name = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func encodedData(_ image: CGImage, type: UTType, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw StorageError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StorageError.encodingFailed }
        return data as Data
    }

    private func downsample(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let scale = min(1, CGFloat(maxPixelSize) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = destination.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
