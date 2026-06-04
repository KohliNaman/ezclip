@preconcurrency import AppKit
import Foundation

final class ScrollingCaptureManager: @unchecked Sendable {
    static let shared = ScrollingCaptureManager()

    private let engine = ContextResolverEngine.shared
    private let captureManager = ScreenCaptureManager.shared

    func captureScrollingPage(bundleId: String) async throws -> [NSImage] {
        // 1. Get page height via JavaScript
        let heightResult = engine.runAppleScript(scrollHeightScript(bundleId: bundleId))
        guard let heightStr = heightResult?.trimmingCharacters(in: .whitespacesAndNewlines),
              let totalHeight = Int(heightStr),
              totalHeight > 0 else {
            throw ScrollingError.cannotReadPageHeight
        }

        // 2. Get viewport height
        let vpResult = engine.runAppleScript(viewportHeightScript(bundleId: bundleId))
        let viewportHeight = vpResult.flatMap(Int.init) ?? 800

        // 3. Calculate scrolls (with 10% overlap to help stitching)
        let overlap = Double(viewportHeight) * 0.1
        let effectiveScroll = Double(viewportHeight) - overlap
        let scrollCount = max(1, Int(ceil(Double(totalHeight) / effectiveScroll)))

        print("📜 Scrolling capture: \(totalHeight)px total, \(scrollCount) scrolls")

        var images: [NSImage] = []
        for i in 0..<scrollCount {
            let scrollY = min(Int(Double(i) * effectiveScroll), totalHeight - viewportHeight)

            // Scroll
            _ = engine.runAppleScript(scrollToScript(bundleId: bundleId, y: max(0, scrollY)))

            // Wait for render
            try await Task.sleep(nanoseconds: 600_000_000)  // 600ms

            // Capture
            let (image, _) = try await captureManager.captureFrontmostWindow()
            images.append(image)
        }

        // Scroll back to top
        _ = engine.runAppleScript(scrollToScript(bundleId: bundleId, y: 0))

        return images
    }

    func stitchImages(_ images: [NSImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }

        let totalHeight = images.reduce(CGFloat(0)) { $0 + $1.size.height }
        let maxWidth = images.map(\.size.width).max() ?? 0

        let stitched = NSImage(size: NSSize(width: maxWidth, height: totalHeight))
        stitched.lockFocus()

        var yOffset: CGFloat = 0
        for image in images {
            image.draw(
                in: NSRect(x: 0, y: yOffset, width: maxWidth, height: image.size.height),
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0
            )
            yOffset += image.size.height
        }

        stitched.unlockFocus()
        return stitched
    }

    // MARK: - AppleScript helpers

    private func scrollHeightScript(bundleId: String) -> String {
        switch bundleId {
        case "com.apple.Safari":
            return "tell application \"Safari\" to do JavaScript \"Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight, document.documentElement.offsetHeight)\" in front document"
        case "com.google.Chrome":
            return "tell application \"Google Chrome\" to execute front window's active tab javascript \"Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight, document.documentElement.offsetHeight)\""
        default:
            return "tell application \"Safari\" to do JavaScript \"Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)\" in front document"
        }
    }

    private func viewportHeightScript(bundleId: String) -> String {
        switch bundleId {
        case "com.apple.Safari":
            return "tell application \"Safari\" to do JavaScript \"window.innerHeight\" in front document"
        case "com.google.Chrome":
            return "tell application \"Google Chrome\" to execute front window's active tab javascript \"window.innerHeight\""
        default:
            return "tell application \"Safari\" to do JavaScript \"window.innerHeight\" in front document"
        }
    }

    private func scrollToScript(bundleId: String, y: Int) -> String {
        switch bundleId {
        case "com.apple.Safari":
            return "tell application \"Safari\" to do JavaScript \"window.scrollTo(0, \(y))\" in front document"
        case "com.google.Chrome":
            return "tell application \"Google Chrome\" to execute front window's active tab javascript \"window.scrollTo(0, \(y))\""
        default:
            return "tell application \"Safari\" to do JavaScript \"window.scrollTo(0, \(y))\" in front document"
        }
    }
}

enum ScrollingError: LocalizedError {
    case cannotReadPageHeight
    case unsupportedBrowser

    var errorDescription: String? {
        switch self {
        case .cannotReadPageHeight: "Could not read page height. Make sure a webpage is open."
        case .unsupportedBrowser: "Scrolling capture is only supported in Safari and Chrome."
        }
    }
}
