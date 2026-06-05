import SwiftUI

struct CaptureDetailView: View {
    let capture: Capture
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: LibraryViewModel

    @State private var fullImage: NSImage?
    @State private var notes: String = ""
    @State private var isEditingNotes = false

    var body: some View {
        ZStack {
            // Tap-to-dismiss: clicking empty space around content dismisses.
            // Buttons and controls sit on top and consume taps first,
            // so only clicks on margins/whitespace trigger dismissal.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Toolbar
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Full image
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
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(height: 300)
                            .overlay(ProgressView())
                    }

                    // Context details
                    contextSection

                    // Notes
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
                                    // Debounced save
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

                    // Metadata
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
                .padding(20)
            }
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 600)
        .task {
            fullImage = ImageStorageManager.shared.fullImage(for: capture)
            notes = capture.notes ?? ""
        }
        } // ZStack
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
                genericContext
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
                Label(song, systemImage: "music.note")
                    .font(.body)
            }
            if let artist = capture.artistName {
                Label(artist, systemImage: "person.fill")
                    .font(.callout)
            }
            if let album = capture.albumName {
                Label(album, systemImage: "square.stack.fill")
                    .font(.callout)
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
                Label(fileName, systemImage: "doc.richtext")
                    .font(.body)
            }
            if let pageName = capture.designPageName {
                Label(pageName, systemImage: "rectangle.split.1x2")
                    .font(.callout)
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

    private var genericContext: some View {
        Text(capture.windowTitle)
            .font(.body)
    }

    // MARK: - Helpers

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
