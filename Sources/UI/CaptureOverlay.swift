import AppKit
import SwiftUI

/// Notch-area capture feedback, mimicking macOS camera/mic indicators.
///
/// Appears as a small pill to the RIGHT of the notch that springs open
/// showing a shutter icon + "Captured", holds briefly, then collapses.
/// Never steals focus, ignores clicks.
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
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 40)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
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

        // Position: right side of notch, at menu bar level
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let screenWidth = screenFrame.width
            let screenHeight = screenFrame.height

            // On notched Macs, the menu bar is taller (~37pt vs 24pt).
            // The notch occupies roughly center 160pt of the menu bar.
            // Menu bar items live on the left (Apple menu) and right
            // (status icons). We position on the right side.
            //
            // Detect notch: if visibleFrame.maxY < screenFrame.maxY,
            // there's a menu bar occupying the top. The notch is at
            // horizontal center.
            let menuBarHeight = screenFrame.height - screen.visibleFrame.maxY
            let hasNotch = menuBarHeight > 25 // taller menu bar = notch present

            // X: right of notch center area
            let notchCenterX = screenFrame.midX
            let notchHalfWidth: CGFloat = hasNotch ? 85 : 0
            let pillX = notchCenterX + notchHalfWidth + 12

            // Y: centered vertically in the menu bar
            let menuBarCenterY = screenHeight - (menuBarHeight / 2)
            let pillY = menuBarCenterY - 20 // panel height is 40, so half = 20

            panel.setFrameOrigin(NSPoint(x: pillX, y: pillY))
        }

        panel.orderFront(nil)
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.panel?.close()
            self?.panel = nil
        }
    }
}

// MARK: - SwiftUI Overlay

/// Animation timeline:
///   0.00s: invisible dot (12pt)
///   0.05s: spring-expand dot → pill (with icon + text)
///   0.80s: hold
///   1.10s: collapse pill → dot
///   1.40s: fade out
private struct NotchOverlayView: View {
    @State private var phase: Phase = .hidden

    private enum Phase: CaseIterable {
        case hidden, expand, hold, collapse, done
    }

    private var pillWidth: CGFloat {
        switch phase {
        case .hidden:   return 32
        case .expand:   return 180
        case .hold:     return 180
        case .collapse: return 32
        case .done:     return 32
        }
    }

    private var pillOpacity: Double {
        switch phase {
        case .hidden:   return 0
        case .expand, .hold: return 1
        case .collapse: return 0.5
        case .done:     return 0
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.shutter.button.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)

            if phase == .expand || phase == .hold {
                Text("Captured")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity.combined(with: .move(edge: .leading)).animation(.easeOut(duration: 0.15)))
            }
        }
        .frame(width: pillWidth, height: 30)
        .opacity(pillOpacity)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pillWidth)
        .animation(.easeInOut(duration: 0.2), value: pillOpacity)
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // 0.00: appear as dot
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            phase = .expand
        }

        // 0.80: hold
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            phase = .hold
        }

        // 1.10: collapse
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeIn(duration: 0.25)) {
                phase = .collapse
            }
        }

        // 1.45: done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            phase = .done
        }
    }
}
