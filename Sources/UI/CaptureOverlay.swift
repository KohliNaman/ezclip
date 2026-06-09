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
            Task { @MainActor [weak self] in
                self?.viewModel.update(from: capture)
            }
        }
    }

    func show(context: ResolvedContext, thumbnail: NSImage? = nil, appName: String = "", bundleId: String = "") {
        panel?.close()
        panel = nil
        dismissTask?.cancel()
        viewModel.phase = .hidden

        viewModel.configure(context: context, appName: appName, bundleId: bundleId, thumbnail: thumbnail)

        let view = NotchOverlayView(viewModel: self.viewModel)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 160)

        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 160),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
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
            panel.setFrameOrigin(NSPoint(x: notchCenterX - 140, y: frame.maxY - safeTop / 2 - 80))
        }

        panel.contentView = hosting
        panel.orderFront(nil)
        self.panel = panel

        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            viewModel.phase = .peek
        }

        // Auto-expand after 0.3s, then auto-dismiss after 2.5s total
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                    viewModel.phase = .expanded
                }
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
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
    @Published var appName: String = ""
    @Published var appIcon: NSImage? = nil
    @Published var contextIcon: String = "app"
    @Published var contextBadge: String = ""
    @Published var screenshotThumbnail: NSImage? = nil
    @Published var contextText: String = ""
    @Published var thumbnail: NSImage? = nil
    @Published var timestamp: String = ""

    func configure(context: ResolvedContext, appName: String, bundleId: String, thumbnail: NSImage?) {
        self.appName = appName
        self.screenshotThumbnail = thumbnail
        self.thumbnail = thumbnail

        // App icon
        if !bundleId.isEmpty {
            appIcon = NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == bundleId }?
                .icon
        }

        // Context icon and badge
        switch context.contextType {
        case .website:
            contextIcon = "globe"
            if let url = context.url, let host = URL(string: url)?.host {
                contextBadge = "🔗 \(host)"
            } else if let pageTitle = context.pageTitle {
                contextBadge = "🔗 \(pageTitle)"
            } else {
                contextBadge = "🔗 \(appName)"
            }
        case .music:
            contextIcon = "music.note"
            if let song = context.songName, let artist = context.artistName {
                contextBadge = "🎵 \(song) — \(artist)"
            } else if let song = context.songName {
                contextBadge = "🎵 \(song)"
            } else {
                contextBadge = "🎵 \(appName)"
            }
        case .design:
            contextIcon = "paintbrush"
            contextBadge = "🎨 \(context.designFileName ?? appName)"
        case .file:
            contextIcon = "doc"
            contextBadge = "📄 \(context.filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? appName)"
        case .generic:
            contextIcon = "app"
            contextBadge = appName
        }
    }

    func update(from capture: Capture) {
        contextText = capture.contextDescription
        let path = capture.thumbnailPath
        thumbnail = NSImage(contentsOfFile: path)
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

    private var pillWidth: CGFloat {
        switch viewModel.phase {
        case .peek: return 120
        case .expanded: return 280
        default: return 120
        }
    }

    private var pillHeight: CGFloat {
        switch viewModel.phase {
        case .peek: return 32
        case .expanded: return viewModel.screenshotThumbnail != nil ? 140 : 100
        default: return 32
        }
    }

    private var pillCornerRadius: CGFloat {
        switch viewModel.phase {
        case .peek: return 16
        case .expanded: return 20
        default: return 16
        }
    }

    var body: some View {
        ZStack {
            NotchPillShape(cornerRadius: pillCornerRadius)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(
                    NotchPillShape(cornerRadius: pillCornerRadius)
                        .stroke(.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                .compositingGroup()

            content
                .padding(.horizontal, viewModel.phase == .expanded ? 12 : 8)
                .padding(.vertical, viewModel.phase == .expanded ? 12 : 6)
        }
        .frame(width: pillWidth, height: pillHeight)
        .opacity(phaseOpacity)
        .scaleEffect(phaseScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.spring(response: viewModel.phase == .dismissed ? 0.45 : 0.42,
                           dampingFraction: viewModel.phase == .dismissed ? 1.0 : 0.8),
                   value: viewModel.phase)
        .sensoryFeedback(.alignment, trigger: viewModel.phase)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.phase == .expanded {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if let icon = viewModel.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    Text(viewModel.appName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: viewModel.contextIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text(viewModel.contextBadge)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)

                if let thumb = viewModel.screenshotThumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        } else {
            HStack(spacing: 6) {
                if let icon = viewModel.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text(viewModel.appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
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
