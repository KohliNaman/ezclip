import AppKit
import SwiftUI

/// Brief overlay animation shown when a screenshot is captured.
/// Displays a subtle bezel flash that fades out, giving visual feedback
/// that the double-press ⌘ was recognized and a capture was taken.
@MainActor
final class CaptureOverlay {
    static let shared = CaptureOverlay()

    private var panel: NSPanel?

    private init() {}

    /// Show the capture feedback overlay. Auto-dismisses after the animation.
    func show() {
        // If already showing, remove and restart
        panel?.close()
        panel = nil

        let content = CaptureOverlayView()

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 60)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .floating
        panel.contentView = hosting

        // Center on the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = panel.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel

        // Auto-dismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.panel?.close()
            self?.panel = nil
        }
    }
}

// MARK: - SwiftUI Overlay Content

private struct CaptureOverlayView: View {
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.shutter.button.fill")
                .font(.title2)
                .foregroundStyle(.white)

            Text("Captured!")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.75))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                opacity = 1
                scale = 1
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.8)) {
                opacity = 0
                scale = 0.9
            }
        }
    }
}
