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
        NSPasteboard.general.writeObjects([image])

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
}
