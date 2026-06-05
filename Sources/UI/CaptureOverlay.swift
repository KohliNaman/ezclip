import AppKit
import SwiftUI

/// Notch-area capture feedback, mimicking macOS camera/mic indicators.
///
/// Appears as a small dot to the right of the notch that springs open
/// into a pill showing the shutter icon + "Captured", holds briefly,
/// then collapses back. Never steals focus, ignores clicks.
///
/// Positioning: on notched Macs, the dot appears just right of the
/// notch at menu-bar level. On notchless Macs, it appears at the
/// top-center of the screen.
@MainActor
final class CaptureOverlay {
    static let shared = CaptureOverlay()

    private var panel: NSPanel?

    private init() {}

    func show() {
        panel?.close()
        panel = nil

        let content = NotchOverlayView()
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 40)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
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

        // Position: right of notch, at menu-bar level
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let menuBarHeight = screenFrame.height - visibleFrame.maxY

            // Notch is at horizontal center of the screen.
            // Place our pill to the right of the notch area.
            // The notch is roughly 160pt wide, so we start ~100pt right of center.
            let notchRight = screenFrame.midX + 85

            // Y: at the top (menu bar level) vertically centered
            let y = screenFrame.height - menuBarHeight + (menuBarHeight - 40) / 2

            panel.setFrameOrigin(NSPoint(x: notchRight, y: y))
        }

        panel.orderFront(nil)
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.panel?.close()
            self?.panel = nil
        }
    }
}

// MARK: - SwiftUI Overlay

/// A dot-to-pill animation:
///   0.0s: invisible 14pt dot
///   0.1s: spring-expand to pill (dot → icon + text)
///   0.7s: hold
///   1.0s: collapse pill → dot
///   1.3s: fade out
private struct NotchOverlayView: View {
    @State private var phase: Phase = .hidden

    private enum Phase: CaseIterable {
        case hidden, expand, hold, collapse, done
    }

    /// Pill width: dot mode = 28pt (icon only), expanded = full width
    private var pillWidth: CGFloat {
        switch phase {
        case .hidden:   return 28
        case .expand:   return 160
        case .hold:     return 160
        case .collapse: return 28
        case .done:     return 28
        }
    }

    private var shouldShowText: Bool {
        switch phase {
        case .hidden, .collapse, .done: return false
        case .expand, .hold:            return true
        }
    }

    private var pillOpacity: Double {
        switch phase {
        case .hidden:   return 0
        case .expand, .hold: return 1
        case .collapse: return 0.6
        case .done:     return 0
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Icon — scales up from small dot
            Image(systemName: "camera.aperture")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)

            if shouldShowText {
                Text("Captured!")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .frame(width: pillWidth, height: 28)
        .opacity(pillOpacity)
        .background(
            Capsule()
                .fill(.black.opacity(0.82))
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pillWidth)
        .animation(.easeInOut(duration: 0.2), value: shouldShowText)
        .animation(.easeInOut(duration: 0.15), value: pillOpacity)
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // 0.0: appear
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            phase = .expand
        }

        // 0.7: hold
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            phase = .hold
        }

        // 1.0: collapse
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.2)) {
                phase = .collapse
            }
        }

        // 1.3: done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            phase = .done
        }
    }
}
