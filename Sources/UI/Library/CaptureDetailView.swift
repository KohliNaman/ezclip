import SwiftUI
import AppKit

/// Dead-simple detail view. Takes a snapshot of captures at open time,
/// tracks position with a plain Int, navigates by +1/-1. No viewModel
/// index recalculation, no binding ping-pong, no stale state.
///
/// NSEvent monitor intercepts Esc/arrows before any focused view.
/// Click-outside works because this is inside a .popover.
struct SimpleDetailView: View {
    let captures: [Capture]
    @State private var currentIndex: Int
    let onDismiss: () -> Void

    @State private var fullImage: NSImage?
    @State private var notes: String = ""
    @State private var isEditingNotes = false
    @State private var eventMonitor: Any?

    init(captures: [Capture], startIndex: Int, onDismiss: @escaping () -> Void) {
        self.captures = captures
        self._currentIndex = State(initialValue: startIndex)
        self.onDismiss = onDismiss
    }

    private var capture: Capture {
        guard currentIndex >= 0, currentIndex < captures.count else {
            return captures[0]
        }
        return captures[currentIndex]
    }

    private var canGoPrevious: Bool { currentIndex > 0 }
    private var canGoNext: Bool { currentIndex < captures.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    imageView

                    if captures.count > 1 {
                        galleryBar
                    }

                    contextSection
                    notesSection
                    metadataSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 600)
        .onAppear { installKeyMonitor(); loadCapture() }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: currentIndex) { _, _ in loadCapture() }
    }

    // MARK: - Key Monitor

    private func installKeyMonitor() {
        removeKeyMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { return event }

            switch Int(event.keyCode) {
            case 53: onDismiss(); return nil                              // Esc
            case 123: goPrevious(); return nil                            // ←
            case 124: goNext(); return nil                                // →
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Navigation

    private func goPrevious() {
        guard canGoPrevious else { return }
        currentIndex -= 1
    }

    private func goNext() {
        guard canGoNext else { return }
        currentIndex += 1
    }

    private func loadCapture() {
        fullImage = ImageStorageManager.shared.fullImage(for: capture)
        notes = capture.notes ?? ""
        isEditingNotes = false
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.contextDescription)
                    .font(.headline).lineLimit(1)
                Text(capture.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if let url = capture.url, let nsurl = URL(string: url) {
                    Button(action: { NSWorkspace.shared.open(nsurl) }) {
                        Label("Open", systemImage: "safari")
                    }.buttonStyle(.bordered).controlSize(.small)
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    }) { Label("Copy Link", systemImage: "link") }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: capture.screenshotPath)])
                }) { Label("Finder", systemImage: "folder") }
                .buttonStyle(.bordered).controlSize(.small)
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Close (Esc)")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Image

    private var imageView: some View {
        Group {
            if let img = fullImage {
                Image(nsImage: img)
                    .resizable().aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    .onTapGesture { onDismiss() }
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    .frame(height: 300).overlay(ProgressView())
            }
        }
    }

    // MARK: - Gallery Bar

    private var galleryBar: some View {
        HStack(spacing: 12) {
            Button(action: goPrevious) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).disabled(!canGoPrevious)
            Text("\(currentIndex + 1) of \(captures.count)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button(action: goNext) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).disabled(!canGoNext)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 4)
    }

    // MARK: - Context

    @ViewBuilder
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(capture.contextType.displayName, systemImage: capture.contextType.iconName)
                .font(.headline).foregroundStyle(.secondary)
            switch capture.contextType {
            case .website: websiteView
            case .music:   musicView
            case .design:  designView
            case .file:    fileView
            case .generic: Text(capture.windowTitle).font(.body)
            }
        }
        .padding(14).background(.quaternary.opacity(0.3)).cornerRadius(10)
    }

    private var websiteView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = capture.pageTitle { Text(t).font(.body).fontWeight(.medium) }
            if let u = capture.url {
                HStack(spacing: 6) {
                    if let fp = capture.faviconPath, let fi = NSImage(contentsOfFile: fp) {
                        Image(nsImage: fi).resizable().frame(width: 16, height: 16).cornerRadius(3)
                    }
                    Text(u).font(.callout).foregroundColor(.blue).lineLimit(2)
                        .onTapGesture { if let nsurl = URL(string: u) { NSWorkspace.shared.open(nsurl) } }
                }
            }
        }
    }

    private var musicView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = capture.songName { Label(s, systemImage: "music.note").font(.body) }
            if let a = capture.artistName { Label(a, systemImage: "person.fill").font(.callout) }
            if let al = capture.albumName { Label(al, systemImage: "square.stack.fill").font(.callout) }
        }
    }

    private var designView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let f = capture.designFileName { Label(f, systemImage: "doc.richtext").font(.body) }
            if let p = capture.designPageName { Label(p, systemImage: "rectangle.split.1x2").font(.callout) }
        }
    }

    private var fileView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = capture.filePath {
                Label(URL(fileURLWithPath: p).lastPathComponent, systemImage: "folder.fill").font(.body)
                Text(p).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes").font(.headline)
                Spacer()
                if !notes.isEmpty { Button("Done") { isEditingNotes = false }.buttonStyle(.plain).font(.caption) }
            }
            if isEditingNotes || notes.isEmpty {
                TextEditor(text: $notes).font(.body).frame(minHeight: 100)
                    .padding(4).background(.quaternary.opacity(0.3)).cornerRadius(6)
            } else {
                Text(notes).font(.body).foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { isEditingNotes = true }
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            row("App", capture.appName)
            row("Bundle ID", capture.appBundleId)
            row("Window", capture.windowTitle)
            if capture.isScrolling, let i = capture.scrollIndex { row("Slice", "#\(i + 1)") }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k).font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(v).font(.caption).lineLimit(2)
        }
    }
}
