import AppKit
import SwiftUI

/// Minimal notch-area animation shown when a screenshot is captured.
/// Mimics macOS's camera/mic indicator style: a pill expanding horizontally
/// from the notch area, showing a shutter icon and brief text, then collapsing.
///
/// Design goals:
/// - Feels native — like the system indicators
/// - Brief (1.2s total) — doesn't interrupt workflow
/// - Non-interactive — ignores clicks, doesn't steal focus
@MainActor
final class CaptureOverlay {
    static let shared = CaptureOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchOverlayView>?

    private init() {}

    /// Show the notch-expanding capture feedback. Auto-dismisses after animation.
    func show() {
        // Dismiss any existing overlay cleanly
        panel?.close()
        panel = nil

        let content = NotchOverlayView()

        // Pill size: 180×36 — compact, notch-friendly
        let pillWidth: CGFloat = 180
        let pillHeight: CGFloat = 36

        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        self.hostingView = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))

        panel.contentView = hosting

        // Position just below the notch: centered horizontally, near top
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame

            // Center horizontally
            let x = screenFrame.midX - pillWidth / 2

            // Just below the menu bar (notch area)
            // visibleFrame.minY gives the bottom of the menu bar area
            // screenFrame.height - visibleFrame.maxY gives menu bar height
            let menuBarHeight = screenFrame.height - visibleFrame.maxY
            let y = screenFrame.height - menuBarHeight - pillHeight - 6  // 6pt gap below notch

            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel

        // Auto-dismiss after animation completes (1.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.panel?.close()
            self?.panel = nil
            self?.hostingView = nil
        }
    }
}

// MARK: - SwiftUI Overlay

/// A pill that expands from a small dot (like the notch indicator)
/// to reveal an icon + "Captured" text, holds briefly, then collapses back.
private struct NotchOverlayView: View {
    @State private var phase: AnimationPhase = .hidden

    private enum AnimationPhase {
        case hidden    // 0: invisible dot
        case expand    // 1: expanding outward
        case hold      // 2: fully visible
        case collapse  // 3: shrinking back
        case done      // 4: gone (panel will close)
    }

    // Derived values from phase
    private var pillWidth: CGFloat {
        switch phase {
        case .hidden:   return 36   // just the icon circle
        case .expand:   return 180  // full pill
        case .hold:     return 180
        case .collapse: return 36
        case .done:     return 36
        }
    }

    private var pillOpacity: Double {
        switch phase {
        case .hidden:   return 0
        case .expand:   return 1
        case .hold:     return 1
        case .collapse: return 0
        case .done:     return 0
        }
    }

    private var labelOpacity: Double {
        switch phase {
        case .hidden:   return 0
        case .expand:   return 1
        case .hold:     return 1
        case .collapse: return 0
        case .done:     return 0
        }
    }

    private var iconScale: CGFloat {
        switch phase {
        case .hidden:   return 0.6
        case .expand:   return 1.0
        case .hold:     return 1.0
        case .collapse: return 0.6
        case .done:     return 0.6
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Shutter icon (always centered in the pill's left portion)
            Image(systemName: "camera.shutter.button")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .scaleEffect(iconScale)

            // "Captured!" label (reveals during expand)
            Text("Captured!")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .opacity(labelOpacity)
                .padding(.leading, 6)
        }
        .frame(width: pillWidth, height: 36)
        .opacity(pillOpacity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onAppear {
            runAnimation()
        }
    }

    private func runAnimation() {
        // Phase 1: appear from notch (0 → 180pt, spring)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            phase = .expand
        }

        // Phase 2: hold (visible for ~0.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                phase = .hold
            }
        }

        // Phase 3: collapse (180 → 36pt, ease-in)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.25)) {
                phase = .collapse
            }
        }

        // Phase 4: done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            phase = .done
        }
    }
}
