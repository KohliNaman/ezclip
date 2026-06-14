@preconcurrency import AppKit
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenCaptureManager: NSObject {
    static let shared = ScreenCaptureManager()

    func captureFrontmostWindow() async throws -> (image: NSImage, windowInfo: WindowInfo) {
        // Get frontmost app
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            throw CaptureError.noFrontmostApp
        }

        let appName = frontApp.localizedName ?? "Unknown"

        // Get shareable content to find the window
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.current
        } catch {
            throw CaptureError.permissionDenied
        }

        // Find the frontmost window
        let candidateWindows = shareableContent.windows.filter { window in
            window.owningApplication?.bundleIdentifier == bundleId &&
            window.isOnScreen &&
            window.frame.width > 100 &&
            window.frame.height > 100 &&
            !window.looksLikeDesktopLayer(on: NSScreen.main)
        }

        // Prefer titled app windows. Finder exposes the desktop as an on-screen
        // window, so largest-window selection can otherwise capture icons only.
        let targetWindow: SCWindow
        if let titled = candidateWindows
            .filter({ ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })
            .max(by: { a, b in
                a.capturePriority < b.capturePriority
            }) {
            targetWindow = titled
        } else if let main = candidateWindows.max(by: { a, b in
            a.capturePriority < b.capturePriority
        }) {
            targetWindow = main
        } else {
            throw CaptureError.windowNotFound
        }

        // Use CGWindowListCreateImage for reliable single-frame capture
        // ScreenCaptureKit's streaming API is overkill for one frame
        let windowID = targetWindow.windowID

        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw CaptureError.captureFailed
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(
            width: targetWindow.frame.width,
            height: targetWindow.frame.height
        ))

        let windowInfo = WindowInfo(
            appName: appName,
            bundleId: bundleId,
            windowTitle: targetWindow.title ?? appName,
            width: targetWindow.frame.width,
            height: targetWindow.frame.height
        )

        return (nsImage, windowInfo)
    }
}

// MARK: - Types

struct WindowInfo {
    let appName: String
    let bundleId: String
    let windowTitle: String
    let width: CGFloat
    let height: CGFloat
}

enum CaptureError: LocalizedError {
    case noFrontmostApp
    case windowNotFound
    case captureFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noFrontmostApp: "No frontmost application found."
        case .windowNotFound: "Could not identify a window to capture."
        case .captureFailed: "Screen capture failed."
        case .permissionDenied: "Screen Recording permission is required.\nOpen System Settings → Privacy & Security → Screen Recording, enable ezclip."
        }
    }
}

private extension SCWindow {
    var capturePriority: CGFloat {
        frame.width * frame.height
    }

    func looksLikeDesktopLayer(on screen: NSScreen?) -> Bool {
        guard owningApplication?.bundleIdentifier == "com.apple.finder" else { return false }
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty else { return false }
        guard let screen else { return true }
        let screenFrame = screen.frame
        return frame.width >= screenFrame.width * 0.92 && frame.height >= screenFrame.height * 0.82
    }
}
