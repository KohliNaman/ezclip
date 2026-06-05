import SwiftUI

/// Full-size detail view for a single capture. Supports:
/// - Arrow-key gallery navigation (← → to browse captures)
/// - Escape or click-on-image to dismiss
/// - Full metadata, notes, and context display
struct CaptureDetailView: View {
    let capture: Capture
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: LibraryViewModel

    @State private var fullImage: NSImage?
    @State private var notes: String = ""
    @State private var isEditingNotes = false

    /// Index of this capture in the view model's filtered list.
    private var currentIndex: Int? {
        viewModel.filteredCaptures.firstIndex(where: { $0.id == capture.id })
    }

    /// Total captures available for navigation.
    private var totalCount: Int {
        viewModel.filteredCaptures.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar ──
            toolbar

            Divider()

            // ── Body ──
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Full image — tap to dismiss
                    imageView

                    // Gallery position indicator
                    if let idx = currentIndex, totalCount > 1 {
                        galleryIndicator(current: idx, total: totalCount)
                    }

                    // Context details
                    contextSection

                    // Notes
                    notesSection

                    // Metadata
                    metadataSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 600)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigateToPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateToNext()
            return .handled
        }
        .task {
            fullImage = ImageStorageManager.shared.fullImage(for: capture)
            notes = capture.notes ?? ""
        }
        .onChange(of: capture.id) { _, _ in
            // Reload when navigating to a different capture
            fullImage = ImageStorageManager.shared.fullImage(for: capture)
            notes = capture.notes ?? ""
            isEditingNotes = false
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.contextDescription)
                    .font(.headline)
                    .lineLimit(1)
                Text(capture.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Quick actions
            HStack(spacing: 8) {
                if let url = capture.url, let nsurl = URL(string: url) {
                    Button(action: { NSWorkspace.shared.open(nsurl) }) {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    }) {
                        Label("Copy Link", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: capture.screenshotPath)]
                    )
                }) {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive, action: {
                    Task {
                        await viewModel.deleteCapture(capture)
                        dismiss()
                    }
                }) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Explicit close button — always visible
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Image

    private var imageView: some View {
        Group {
            if let image = fullImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    .onTapGesture {
                        dismiss()
                    }
                    .onTapGesture(count: 2) {
                        // Double-tap also dismisses (belt-and-suspenders)
                        dismiss()
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(height: 300)
                    .overlay(ProgressView())
            }
        }
    }

    // MARK: - Gallery Indicator

    private func galleryIndicator(current: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                navigateToPrevious()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(current == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Text("\(current + 1) of \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                navigateToNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .disabled(current >= total - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Navigation

    private func navigateToPrevious() {
        guard let idx = currentIndex, idx > 0 else { return }
        let prevCapture = viewModel.filteredCaptures[idx - 1]
        // Trigger a new detail view for the previous capture
        // by dismissing and immediately setting selectedCapture
        viewModel.selectedCapture = prevCapture
    }

    private func navigateToNext() {
        guard let idx = currentIndex, idx < totalCount - 1 else { return }
        let nextCapture = viewModel.filteredCaptures[idx + 1]
        viewModel.selectedCapture = nextCapture
    }

    // MARK: - Context Section

    @ViewBuilder
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(capture.contextType.displayName, systemImage: capture.contextType.iconName)
                .font(.headline)
                .foregroundStyle(.secondary)

            switch capture.contextType {
            case .website:
                websiteContext
            case .music:
                musicContext
            case .design:
                designContext
            case .file:
                fileContext
            case .generic:
                Text(capture.windowTitle)
                    .font(.body)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(10)
    }

    private var websiteContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pageTitle = capture.pageTitle {
                Text(pageTitle)
                    .font(.body)
                    .fontWeight(.medium)
            }
            if let url = capture.url {
                HStack(spacing: 6) {
                    if let favPath = capture.faviconPath,
                       let favImage = NSImage(contentsOfFile: favPath) {
                        Image(nsImage: favImage)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .cornerRadius(3)
                    }
                    Text(url)
                        .font(.callout)
                        .foregroundColor(.blue)
                        .lineLimit(2)
                        .onTapGesture {
                            if let nsurl = URL(string: url) {
                                NSWorkspace.shared.open(nsurl)
                            }
                        }
                }
            }
        }
    }

    private var musicContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let song = capture.songName {
                Label(song, systemImage: "music.note").font(.body)
            }
            if let artist = capture.artistName {
                Label(artist, systemImage: "person.fill").font(.callout)
            }
            if let album = capture.albumName {
                Label(album, systemImage: "square.stack.fill").font(.callout)
            }
            if let artPath = capture.albumArtPath,
               let artImage = NSImage(contentsOfFile: artPath) {
                Image(nsImage: artImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .cornerRadius(6)
            }
        }
    }

    private var designContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fileName = capture.designFileName {
                Label(fileName, systemImage: "doc.richtext").font(.body)
            }
            if let pageName = capture.designPageName {
                Label(pageName, systemImage: "rectangle.split.1x2").font(.callout)
            }
        }
    }

    private var fileContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = capture.filePath {
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder.fill")
                    .font(.body)
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                if !notes.isEmpty {
                    Button("Edit") { isEditingNotes.toggle() }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
            }

            if isEditingNotes || notes.isEmpty {
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 100)
                    .padding(4)
                    .background(.quaternary.opacity(0.3))
                    .cornerRadius(6)
                    .onChange(of: notes) { _, new in
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await viewModel.updateNotes(new, for: capture)
                        }
                    }

                if !notes.isEmpty {
                    Button("Done") { isEditingNotes = false }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { isEditingNotes = true }
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metadata")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            metadataRow("App", capture.appName)
            metadataRow("Bundle ID", capture.appBundleId)
            metadataRow("Window", capture.windowTitle)
            if capture.isScrolling, let idx = capture.scrollIndex {
                metadataRow("Scroll Slice", "#\(idx + 1)")
            }
            metadataRow("Image", URL(fileURLWithPath: capture.screenshotPath).lastPathComponent)
        }
    }

    private func metadataRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
    }
}
