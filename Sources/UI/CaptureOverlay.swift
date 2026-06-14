import AppKit
import SwiftUI

@MainActor
final class CaptureOverlay {
    static let shared = CaptureOverlay()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchOverlayView>?
    private let state = OverlayState()
    private var dismissTask: Task<Void, Never>?

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
        scheduleDismiss(after: 1.9)
    }

    func showEnriched(_ context: ResolvedContext) {
        guard panel != nil else { return }
        state.contextText = contextSummary(context)
        state.phase = .enriched
        scheduleDismiss(after: 1.6)
    }

    func showFailed() {
        ensurePanel()
        state.phase = .failed
        scheduleDismiss(after: 1.6)
    }

    private func ensurePanel() {
        if panel != nil {
            positionPanel()
            return
        }

        let view = NotchOverlayView(state: state)
        let hosting = NSHostingView(rootView: view)
        let panelSize = calibratedPanelSize()
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

        panel.setContentSize(panelSize)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        positionPanel(panel: panel, panelSize: panelSize)
        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hosting
    }

    private func positionPanel() {
        guard let panel else { return }
        let panelSize = calibratedPanelSize()
        panel.setContentSize(panelSize)
        hostingView?.frame = NSRect(origin: .zero, size: panelSize)
        positionPanel(panel: panel, panelSize: panelSize)
    }

    private func positionPanel(panel: NSPanel, panelSize: NSSize) {
        if let screen = NSScreen.main {
            let frame = screen.frame
            let safeTop = max(screen.safeAreaInsets.top, frame.height - screen.visibleFrame.maxY)
            let notchWidth: CGFloat
            let notchCenterX: CGFloat
            if safeTop > 25,
               let left = screen.auxiliaryTopLeftArea?.width,
               let right = screen.auxiliaryTopRightArea?.width {
                notchWidth = min(max(132, frame.width - left - right), 238)
                notchCenterX = left + (frame.width - left - right) / 2
            } else {
                notchWidth = min(max(frame.width * 0.105, 150), 210)
                notchCenterX = frame.midX
            }
            state.closedNotchWidth = notchWidth

            let x = min(
                max(frame.minX + 8, notchCenterX - panelSize.width / 2),
                frame.maxX - panelSize.width - 8
            )
            let y = frame.maxY - panelSize.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func calibratedPanelSize() -> NSSize {
        guard let screen = NSScreen.main else { return NSSize(width: 500, height: 128) }
        let width = min(max(screen.frame.width * 0.36, 440), 620)
        return NSSize(width: width, height: 132)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.34)) {
                state.phase = .hidden
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
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
    @Published var closedNotchWidth: CGFloat = 170
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
        case .hidden: state.closedNotchWidth
        case .capturing: state.closedNotchWidth + 108
        case .saved: state.thumbnail == nil ? state.closedNotchWidth + 136 : state.closedNotchWidth + 172
        case .enriched: state.closedNotchWidth + 208
        case .failed: state.closedNotchWidth + 124
        }
    }

    private var height: CGFloat {
        switch state.phase {
        case .hidden: 34
        case .capturing: 58
        default: 62
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            leadingContent
            Spacer()
            trailingContent
        }
        .opacity(state.phase == .hidden ? 0.72 : 1)
        .frame(width: width, height: height)
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: state.phase == .hidden ? 16 : 28,
                bottomTrailingRadius: state.phase == .hidden ? 16 : 28,
                topTrailingRadius: 0,
                style: .continuous
            )
                .fill(.black.opacity(0.92))
                .environment(\.colorScheme, .dark)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: state.phase == .hidden ? 16 : 28,
                        bottomTrailingRadius: state.phase == .hidden ? 16 : 28,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .stroke(.white.opacity(state.phase == .hidden ? 0 : 0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(state.phase == .hidden ? 0 : 0.38), radius: 16, y: 5)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: state.phase == .hidden ? 16 : 28,
                bottomTrailingRadius: state.phase == .hidden ? 16 : 28,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .animation(.spring(response: state.phase == .hidden ? 0.52 : 0.72, dampingFraction: state.phase == .hidden ? 1.0 : 0.86), value: width)
        .animation(.spring(response: state.phase == .hidden ? 0.52 : 0.72, dampingFraction: state.phase == .hidden ? 1.0 : 0.86), value: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var leadingContent: some View {
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
                EmptyView()
            }
        default:
            Image(systemName: "camera.shutter.button.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.35), value: state.phase == .capturing)
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        switch state.phase {
        case .enriched:
            Text(state.contextText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
        case .saved:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        default:
            EmptyView()
        }
    }
}
