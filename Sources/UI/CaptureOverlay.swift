import AppKit
import SwiftUI

@MainActor
final class CaptureOverlay {
    static let shared = CaptureOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchOverlayView>?
    private let state = OverlayState()
    private var dismissTask: Task<Void, Never>?
    private let panelSize = NSSize(width: 220, height: 72)

    private init() {}

    func showCapturing(appName: String? = nil, bundleId: String? = nil) {
        ensurePanel()
        dismissTask?.cancel()
        state.appName = appName ?? ""
        state.appIcon = bundleId.flatMap { appIcon(for: $0) }
        state.phase = .capturing
    }

    func showSaved(thumbnail: NSImage?, appName: String, bundleId: String) {
        ensurePanel()
        state.appName = appName
        state.appIcon = appIcon(for: bundleId)
        state.thumbnail = thumbnail
        state.phase = .saved
        scheduleDismiss(after: 1.4)
    }

    func showEnriched(_ context: ResolvedContext) {
        guard panel != nil else { return }
        state.contextText = contextSummary(context)
        state.phase = .enriched
        scheduleDismiss(after: 1.1)
    }

    func showFailed() {
        ensurePanel()
        state.phase = .failed
        scheduleDismiss(after: 1.2)
    }

    private func ensurePanel() {
        if panel != nil { return }

        let view = NotchOverlayView(state: state)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: panelSize)

        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
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
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let frame = screen.frame
            let safeTop = max(screen.safeAreaInsets.top, frame.height - screen.visibleFrame.maxY)
            let notchCenterX: CGFloat
            let notchLeftX: CGFloat
            if safeTop > 25,
               let left = screen.auxiliaryTopLeftArea?.width,
               let right = screen.auxiliaryTopRightArea?.width {
                notchCenterX = left + (frame.width - left - right) / 2
                notchLeftX = left
            } else {
                notchCenterX = frame.midX
                notchLeftX = notchCenterX
            }

            let x: CGFloat
            if safeTop > 25 {
                x = max(frame.minX + 8, notchLeftX - panelSize.width + 16)
            } else {
                x = notchCenterX - panelSize.width / 2
            }
            let y: CGFloat
            if safeTop > 25 {
                y = frame.maxY - max(safeTop, 44) + 6
            } else {
                y = frame.maxY - panelSize.height - 8
            }
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hosting
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.18)) {
                state.phase = .hidden
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            panel?.close()
            panel = nil
            hostingView = nil
        }
    }

    private func appIcon(for bundleId: String) -> NSImage? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }?.icon
    }

    private func contextSummary(_ context: ResolvedContext) -> String {
        switch context.contextType {
        case .website:
            if let url = context.url, let host = URL(string: url)?.host { return host }
            return context.pageTitle ?? "Website"
        case .music:
            if let song = context.songName, let artist = context.artistName { return "\(song) - \(artist)" }
            return context.songName ?? "Music"
        case .design:
            return context.designFileName ?? "Design"
        case .file:
            return context.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "File"
        case .generic:
            return "Saved"
        }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class OverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .hidden
    @Published var appName: String = ""
    @Published var contextText: String = ""
    @Published var appIcon: NSImage?
    @Published var thumbnail: NSImage?
}

private enum OverlayPhase {
    case hidden
    case capturing
    case saved
    case enriched
    case failed
}

@MainActor
private struct NotchOverlayView: View {
    @ObservedObject var state: OverlayState

    private var width: CGFloat {
        switch state.phase {
        case .hidden: 34
        case .capturing: 64
        case .saved: state.thumbnail == nil ? 92 : 132
        case .enriched: 172
        case .failed: 86
        }
    }

    private var height: CGFloat {
        switch state.phase {
        case .hidden: 34
        case .capturing: 40
        default: 44
        }
    }

    private var opacity: Double {
        state.phase == .hidden ? 0 : 1
    }

    var body: some View {
        HStack(spacing: 8) {
            leadIcon

            if state.phase == .enriched {
                Text(state.contextText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
            } else if state.phase == .saved, state.thumbnail != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: width, height: height)
        .opacity(opacity)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.32), radius: 12, y: 4)
        )
        .clipShape(Capsule())
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: width)
        .animation(.easeInOut(duration: 0.16), value: opacity)
        .offset(x: state.phase == .hidden ? 22 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var leadIcon: some View {
        switch state.phase {
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        case .saved, .enriched:
            if let icon = state.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        default:
            Image(systemName: "camera.shutter.button.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating, value: state.phase == .capturing)
        }
    }
}
