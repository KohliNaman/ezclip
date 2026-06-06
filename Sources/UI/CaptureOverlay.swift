import AppKit
import SwiftUI

/// Notch-area capture feedback — small circle with shutter icon.
/// Appears to the right of the notch, springs in, holds, fades out.
/// Never steals focus, ignores clicks. Icon only — no text.
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
        hosting.frame = NSRect(x: 0, y: 0, width: 44, height: 44)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 44, height: 44),
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
            let screenHeight = screenFrame.height

            let menuBarHeight = screenFrame.height - screen.visibleFrame.maxY
            let hasNotch = menuBarHeight > 25

            let notchCenterX = screenFrame.midX
            let notchHalfWidth: CGFloat = hasNotch ? 85 : 0
            let dotX = notchCenterX + notchHalfWidth + 12

            let menuBarCenterY = screenHeight - (menuBarHeight / 2)
            let dotY = menuBarCenterY - 22 // half of 44

            panel.setFrameOrigin(NSPoint(x: dotX, y: dotY))
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

/// Animation: spring-in scale (0 → 1.15 → 1.0), hold, fade out.
/// Icon only — no text, no clipping.
private struct NotchOverlayView: View {
    @State private var phase: Phase = .hidden

    private enum Phase {
        case hidden, spring, hold, fadeOut, done
    }

    private var scale: CGFloat {
        switch phase {
        case .hidden:   return 0.0
        case .spring:   return 1.0
        case .hold:     return 1.0
        case .fadeOut:  return 0.8
        case .done:     return 0.0
        }
    }

    private var opacity: Double {
        switch phase {
        case .hidden:   return 0
        case .spring:   return 1
        case .hold:     return 1
        case .fadeOut:  return 0.3
        case .done:     return 0
        }
    }

    var body: some View {
        Image(systemName: "camera.shutter.button.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .scaleEffect(scale)
            .opacity(opacity)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            )
            .animation(.spring(response: 0.45, dampingFraction: 0.65), value: scale)
            .animation(.easeInOut(duration: 0.2), value: opacity)
            .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // Spring in
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            phase = .spring
        }

        // Hold 0.7s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            phase = .hold
        }

        // Fade out at 1.0s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.3)) {
                phase = .fadeOut
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                phase = .done
            }
        }
    }
}
