import AppKit
import SwiftUI

/// Manages a standalone NSPanel for viewing capture details.
///
/// Why a panel instead of .popover:
///   - Panel becomes key → keyboard events work reliably
///   - No SwiftUI popover view-recreation quirks
///   - Arrow keys and Esc work every time
@MainActor
final class DetailWindow {
    static let shared = DetailWindow()

    private var panel: NSPanel?
    private var onDismiss: (() -> Void)?

    private init() {}

    func show(captures: [Capture], at index: Int, onDismiss: @escaping () -> Void) {
        // Close any existing detail window first
        close()

        self.onDismiss = onDismiss

        // Use @StateObject to give SimpleDetailView stable state
        let detailVM = DetailViewModel(captures: captures, startIndex: index)
        let detailView = SimpleDetailView(viewModel: detailVM) { [weak self] in
            self?.onDismiss?()
            self?.close()
        }

        let hosting = NSHostingView(rootView: detailView)
        hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 640)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.title = "Capture Detail"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.delegate = DetailWindowDelegate.shared
        panel.animationBehavior = .documentWindow

        // Center on screen
        if let screen = NSScreen.main {
            let centerX = screen.visibleFrame.midX - 380
            let centerY = screen.visibleFrame.midY - 320
            panel.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        }

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

    }

    func close() {
        if let panel = panel {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResignKeyNotification,
                object: panel
            )
            panel.delegate = nil
            panel.close()
        }
        panel = nil
        onDismiss = nil
    }

    var isVisible: Bool { panel?.isVisible ?? false }
}

// MARK: - Window Delegate

private final class DetailWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = DetailWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        DetailWindow.shared.close()
    }
}

// MARK: - Detail ViewModel (fixes @State recreation)

/// Simple observable object that holds the detail view state.
/// Unlike @State, this survives view recreations because it's
/// owned by DetailWindow, not by SwiftUI's view graph.
@MainActor
final class DetailViewModel: ObservableObject {
    @Published private(set) var captures: [Capture]
    @Published var currentIndex: Int
    @Published var currentTags: [String] = []

    init(captures: [Capture], startIndex: Int) {
        self.captures = captures
        self.currentIndex = startIndex
        Task { await loadCurrentTags() }
    }

    var capture: Capture {
        guard currentIndex >= 0, currentIndex < captures.count else {
            return captures[0]
        }
        return captures[currentIndex]
    }

    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < captures.count - 1 }

    func goPrevious() {
        guard canGoPrevious else { return }
        currentIndex -= 1
        Task { await loadCurrentTags() }
    }

    func goNext() {
        guard canGoNext else { return }
        currentIndex += 1
        Task { await loadCurrentTags() }
    }

    func updateCurrentNotes(_ notes: String) async {
        guard currentIndex >= 0, currentIndex < captures.count else { return }

        captures[currentIndex].notes = notes.isEmpty ? nil : notes
        let updated = captures[currentIndex]

        do {
            try await DatabaseManager.shared.write { db in
                try updated.update(db)
            }
        } catch {
            print("Failed to update notes: \(error)")
        }
    }

    func loadCurrentTags() async {
        guard currentIndex >= 0, currentIndex < captures.count else { return }
        do {
            currentTags = try await DatabaseManager.shared.tagNames(for: capture.id)
        } catch {
            print("Failed to load tags: \(error)")
            currentTags = []
        }
    }

    func addTag(_ name: String) async {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !currentTags.contains(normalized) else { return }
        await setTags(currentTags + [normalized])
    }

    func removeTag(_ name: String) async {
        await setTags(currentTags.filter { $0 != name })
    }

    private func setTags(_ tags: [String]) async {
        guard currentIndex >= 0, currentIndex < captures.count else { return }
        do {
            try await DatabaseManager.shared.setTagNames(tags, for: capture.id)
            await loadCurrentTags()
            NotificationCenter.default.post(name: .captureTagsChanged, object: nil)
        } catch {
            print("Failed to update tags: \(error)")
        }
    }
}
