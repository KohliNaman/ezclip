@preconcurrency import AppKit
@preconcurrency import SwiftUI

@MainActor
final class CaptureOverlay {
    static let shared = CaptureOverlay()

    private var panel: NotchPanel?
    private var dismissTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private let viewModel = OverlayViewModel()

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .newCaptureCreated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let capture = notification.object as? Capture else { return }
            self?.viewModel.update(from: capture)
        }
    }

    func show() {
        panel?.close()
        panel = nil
        dismissTask?.cancel()
        viewModel.phase = .hidden

        let view = NotchOverlayView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 120)

        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 120),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)

        if let screen = NSScreen.main {
            let frame = screen.frame
            let safeTop = screen.safeAreaInsets.top
            let notchCenterX: CGFloat
            if safeTop > 25, let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width {
                notchCenterX = left + (frame.width - left - right) / 2
            } else {
                notchCenterX = frame.midX
            }
            panel.setFrameOrigin(NSPoint(x: notchCenterX - 140, y: frame.maxY - safeTop / 2 - 60))
        }

        panel.contentView = hosting
        panel.orderFront(nil)
        self.panel = panel

        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            viewModel.phase = .peek
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            if !Task.isCancelled { await dismiss() }
        }
    }

    func dismiss() {
        panel?.ignoresMouseEvents = true
        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
            viewModel.phase = .dismissed
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled {
                panel?.close()
                self.panel = nil
            }
        }
    }

    func cancelDismiss() {
        dismissTask?.cancel()
    }

    func scheduleDismiss() {
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !Task.isCancelled { await dismiss() }
        }
    }
}

// MARK: - Custom Panel

private class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View Model

@MainActor
final class OverlayViewModel: ObservableObject {
    @Published var phase: OverlayPhase = .hidden
    @Published var contextText: String = ""
    @Published var thumbnail: NSImage? = nil
    @Published var timestamp: String = ""

    func update(from capture: Capture) {
        contextText = capture.contextDescription
        if let path = capture.thumbnailPath {
            thumbnail = NSImage(contentsOfFile: path)
        }
        timestamp = DateFormatter.localizedString(from: capture.timestamp, dateStyle: .short, timeStyle: .short)
    }
}

// MARK: - Phase

enum OverlayPhase: Equatable {
    case hidden, peek, expanded, dismissed
}

// MARK: - SwiftUI View

@MainActor
struct NotchOverlayView: View {
    @StateObject var viewModel: OverlayViewModel

    private var phaseOpacity: Double {
        switch viewModel.phase {
        case .hidden, .dismissed: return 0
        case .peek, .expanded: return 1
        }
    }

    private var phaseScale: CGFloat {
        switch viewModel.phase {
        case .hidden: return 0.0
        case .dismissed: return 0.8
        case .peek, .expanded: return 1.0
        }
    }

    var body: some View {
        ZStack {
            NotchPillShape(cornerRadius: viewModel.phase == .expanded ? 16 : 22)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    NotchPillShape(cornerRadius: viewModel.phase == .expanded ? 16 : 22)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .compositingGroup()
                .drawingGroup()

            content
                .contentTransition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
                .padding(.horizontal, viewModel.phase == .expanded ? 12 : 10)
                .padding(.vertical, viewModel.phase == .expanded ? 12 : 8)
        }
        .frame(width: viewModel.phase == .expanded ? 280 : 160, height: viewModel.phase == .expanded ? 120 : 44)
        .opacity(phaseOpacity)
        .scaleEffect(phaseScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onHover { hovering in
            if hovering {
                CaptureOverlay.shared.cancelDismiss()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                    viewModel.phase = .expanded
                }
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
                    viewModel.phase = .peek
                }
                CaptureOverlay.shared.scheduleDismiss()
            }
        }
        .sensoryFeedback(.alignment, trigger: viewModel.phase)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.phase == .expanded {
            HStack(spacing: 10) {
                if let thumb = viewModel.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.contextText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(viewModel.timestamp)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "camera.shutter.button.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                if !viewModel.contextText.isEmpty {
                    Text(viewModel.contextText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Morphing Shape

struct NotchPillShape: Shape {
    var cornerRadius: CGFloat
    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
}
