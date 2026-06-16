import AppKit
/// Manages clipboard copy of screenshots with auto-expiry.
///
/// When a screenshot is captured, it's copied to the clipboard.
/// After 10 minutes, the clipboard is cleared IF it still contains
/// image data (prevents stale clipboard bloat but won't wipe
/// something the user copied manually in the meantime).
@MainActor
final class ClipboardManager {
    static let shared = ClipboardManager()

    private var expiryWorkItem: DispatchWorkItem?
    private let expirySeconds: TimeInterval = 600 // 10 minutes

    private init() {}

    /// Copies the image to clipboard and schedules auto-clear.
    func copyToClipboard(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        if let data = pngDataForClipboard(image) {
            NSPasteboard.general.setData(data, forType: .png)
        } else {
            NSPasteboard.general.writeObjects([image])
        }

        scheduleExpiry()
    }

    func copyToClipboard(_ images: [NSImage]) {
        guard !images.isEmpty else { return }
        if images.count == 1, let image = images.first {
            copyToClipboard(image)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(images.map { downsampled($0, maxDimension: 2400) })
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.clearIfOurs()
        }
        expiryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + expirySeconds,
            execute: workItem
        )
    }

    /// Clears clipboard only if it still looks like our screenshot
    /// (has image data). If the user copied text/files since, leave it.
    private func clearIfOurs() {
        let types = NSPasteboard.general.types ?? []
        if types.contains(.tiff) || types.contains(.png) {
            NSPasteboard.general.clearContents()
        }
    }

    private func pngDataForClipboard(_ image: NSImage) -> Data? {
        let maxDimension: CGFloat = 2400
        let source = downsampled(image, maxDimension: maxDimension)
        guard let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = source.size
        return rep.representation(using: .png, properties: [:])
    }

    private func downsampled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return image }

        let scale = maxDimension / largest
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()
        return resized
    }
}
