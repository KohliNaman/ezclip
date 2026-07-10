import SwiftUI
import AppKit

/// Detail view for a single capture. Uses a DetailViewModel for stable
/// state (no @State index that gets recreated by SwiftUI).
///
/// Hosted in an NSPanel managed by DetailWindow — not a SwiftUI popover.
/// NSPanel gives us reliable keyboard events and click-outside dismiss.
struct SimpleDetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    let onDismiss: () -> Void

    @State private var previewImage: NSImage?
    @State private var notes: String = ""
    @State private var newTag: String = ""
    @State private var isEditingNotes = false
    @State private var eventMonitor: Any?
    @State private var zoomScale: CGFloat = 1.0
    @State private var activeMagnification: CGFloat = 1.0
    @State private var isGeneratingAITags = false
    @State private var isRetryingDesignContext = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    imageView

                    if viewModel.captures.count > 1 {
                        galleryBar
                    }

                    contextSection
                    if let analysis = viewModel.currentAIContext {
                        analysisSection(analysis)
                    }
                    if let designContext = BrowserDesignContextStore.decode(viewModel.capture.designContextJSON) {
                        designContextSection(designContext)
                    } else if viewModel.capture.contextType == .website {
                        designContextMissingSection
                    }
                    tagsSection
                    notesSection
                    metadataSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 560)
        .onAppear { installKeyMonitor(); loadCapture() }
        .onDisappear {
            removeKeyMonitor()
            previewImage = nil
        }
        .onChange(of: viewModel.currentIndex) { _, _ in loadCapture() }
        .onReceive(NotificationCenter.default.publisher(for: .captureAIContextChanged)) { _ in
            Task { await viewModel.loadCurrentAIContext() }
        }
    }

    // MARK: - Key Monitor

    private func installKeyMonitor() {
        removeKeyMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command,
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                copyCurrentImage()
                return nil
            }
            guard !mods.contains(.command), !mods.contains(.option), !mods.contains(.control) else { return event }

            switch Int(event.keyCode) {
            case 53: onDismiss(); return nil                              // Esc
            case 36, 76:
                if isEditingNotes {
                    saveNotes()
                    return nil
                }
                return event                                               // Return / Enter
            case 123: viewModel.goPrevious(); return nil                  // ←
            case 124: viewModel.goNext(); return nil                      // →
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Load

    private func loadCapture() {
        previewImage = ImageStorageManager.shared.previewImage(for: viewModel.capture)
        notes = viewModel.capture.notes ?? ""
        newTag = ""
        isEditingNotes = notes.isEmpty
        zoomScale = 1.0
        activeMagnification = 1.0
        Task { await viewModel.loadCurrentTags() }
        Task { await viewModel.loadCurrentAIContext() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.capture.contextDescription)
                    .font(.headline).lineLimit(1)
                Text(viewModel.capture.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                if let url = viewModel.capture.url, let nsurl = URL(string: url) {
                    HStack(spacing: 5) {
                        Button(action: { copyText(url) }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("Copy Link")
                        Text("Link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(action: { NSWorkspace.shared.open(nsurl) }) {
                            Image(systemName: "safari")
                        }
                        .buttonStyle(.plain)
                        .help("Open Link")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quaternary.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                HStack(spacing: 5) {
                    Button(action: copyCurrentImage) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy Image")
                    Text("Image")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(action: showCurrentInFinder) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Button(action: generateAITags) {
                    if isGeneratingAITags || viewModel.currentAIContext?.status == .pending {
                        Label("Tagging", systemImage: "sparkles")
                    } else {
                        Label("AI Tags", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isGeneratingAITags || viewModel.currentAIContext?.status == .pending)
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
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let zoom = clampedZoom(zoomScale * activeMagnification)
            let isZoomed = zoom > 1.01

            Group {
                if let img = previewImage {
                    imageViewport(img, viewportSize: viewportSize, zoom: zoom, isZoomed: isZoomed)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: viewportSize.width, height: viewportSize.height)
            .background(.quaternary.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        }
        .frame(height: 380)
    }

    @ViewBuilder
    private func imageViewport(_ img: NSImage, viewportSize: CGSize, zoom: CGFloat, isZoomed: Bool) -> some View {
        Group {
            if isZoomed {
                ScrollView([.vertical, .horizontal]) {
                    zoomableImage(img, viewportSize: viewportSize, zoom: zoom)
                }
            } else {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: viewportSize.width, height: viewportSize.height)
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    activeMagnification = value
                }
                .onEnded { value in
                    zoomScale = clampedZoom(zoomScale * value)
                    activeMagnification = 1.0
                }
        )
        .onTapGesture(count: 2) {
            zoomScale = zoomScale == 1.0 ? 2.0 : 1.0
        }
    }

    private func zoomableImage(_ img: NSImage, viewportSize: CGSize, zoom: CGFloat) -> some View {
        Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: viewportSize.width, height: viewportSize.height)
            .scaleEffect(zoom, anchor: .center)
            .frame(
                width: viewportSize.width * zoom,
                height: viewportSize.height * zoom
            )
    }

    // MARK: - Gallery Bar

    private var galleryBar: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.goPrevious) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).disabled(!viewModel.canGoPrevious)
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(viewModel.currentIndex + 1) of \(viewModel.captures.count)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button(action: viewModel.goNext) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).disabled(!viewModel.canGoNext)
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(maxWidth: .infinity).padding(.vertical, 4)
    }

    // MARK: - Context

    @ViewBuilder
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(viewModel.capture.contextType.displayName, systemImage: viewModel.capture.contextType.iconName)
                .font(.headline).foregroundStyle(.secondary)
            switch viewModel.capture.contextType {
            case .website: websiteView
            case .music:   musicView
            case .design:  designView
            case .file:    fileView
            case .generic: Text(viewModel.capture.windowTitle).font(.body)
            }
        }
        .padding(14).background(.quaternary.opacity(0.3)).cornerRadius(10)
    }

    private var websiteView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = viewModel.capture.pageTitle { Text(t).font(.body).fontWeight(.medium) }
            if let u = viewModel.capture.url {
                HStack(spacing: 6) {
                    if let fp = viewModel.capture.faviconPath,
                       let fi = ImageStorageManager.shared.faviconImage(path: fp) {
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
            if let s = viewModel.capture.songName { Label(s, systemImage: "music.note").font(.body) }
            if let a = viewModel.capture.artistName { Label(a, systemImage: "person.fill").font(.callout) }
            if let al = viewModel.capture.albumName { Label(al, systemImage: "square.stack.fill").font(.callout) }
        }
    }

    private var designView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let f = viewModel.capture.designFileName { Label(f, systemImage: "doc.richtext").font(.body) }
            if let p = viewModel.capture.designPageName { Label(p, systemImage: "rectangle.split.1x2").font(.callout) }
        }
    }

    private var fileView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = viewModel.capture.filePath {
                Label(URL(fileURLWithPath: p).lastPathComponent, systemImage: "folder.fill").font(.body)
                Text(p).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
        }
    }

    private func analysisSection(_ analysis: CaptureAIContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(analysis.kind.displayName, systemImage: analysis.kind.iconName)
                    .font(.headline)
                Spacer()
                Text(analysis.provider == "local" ? "On-device" : analysis.provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let title = analysis.suggestedTitle, !title.isEmpty {
                Text(title).font(.body.weight(.medium))
            }
            if let summary = analysis.summary, !summary.isEmpty {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            if let ocr = analysis.ocrText, !ocr.isEmpty {
                DisclosureGroup("Searchable text") {
                    Text(ocr)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func designContextSection(_ context: BrowserDesignContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Design Context", systemImage: "paintpalette.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
            DesignContextView(context: context)
        }
        .padding(14)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(10)
    }

    private var designContextMissingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(designContextStatusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(designContextStatusTitle)
                        .font(.headline)
                    Text(viewModel.capture.designContextMessage ?? "ezclip saved the screenshot and link, but no browser design context was attached.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    retryDesignEnrichment()
                } label: {
                    if isRetryingDesignContext {
                        Label("Retrying", systemImage: "arrow.clockwise")
                    } else {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRetryingDesignContext)

                Button {
                    copyText(BrowserExtensionDiagnostics.diagnosticsText())
                } label: {
                    Label("Diagnostics", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let source = viewModel.capture.designContextSource {
                    Text(source)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let updatedAt = viewModel.capture.designContextUpdatedAt {
                    Text(updatedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.yellow.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.yellow.opacity(0.35), lineWidth: 0.5)
        )
        .cornerRadius(10)
    }

    private var designContextStatusTitle: String {
        viewModel.capture.designEnrichmentStatus?.displayName ?? "Design context missing"
    }

    private var designContextStatusColor: Color {
        switch viewModel.capture.designEnrichmentStatus {
        case .enriched: .green
        case .nativeHostMissing, .extensionMissing, .transportFailed: .red
        case .stalePayload, .urlMismatch, .emptyPayload, .restrictedPage, .none: .yellow
        }
    }

    private func retryDesignEnrichment() {
        guard !isRetryingDesignContext else { return }
        isRetryingDesignContext = true
        Task {
            await viewModel.retryDesignEnrichment()
            isRetryingDesignContext = false
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tags", systemImage: "tag")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                aiStatusView
            }

            let visibleTags = visibleTagRecords
            if !visibleTags.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(visibleTags, id: \.self) { tag in
                        HStack(spacing: 6) {
                            TagSymbolView(symbol: tag.tagSymbol, size: 12)
                            Text(tag.name)
                                .font(.caption)
                                .lineLimit(1)
                            Button {
                                Task { await viewModel.removeTag(tag.name) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.65))
                        .clipShape(Capsule())
                    }
                }
            }

            let hiddenTags = hiddenTagRecords
            if !hiddenTags.isEmpty {
                DisclosureGroup("Hidden search metadata") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(hiddenTags, id: \.self) { tag in
                            Text(tag.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary.opacity(0.35))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Add tags like pricing page, landing page", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTagsFromField() }
                Button("Add") { addTagsFromField() }
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let aiStatusMessage {
                Text(aiStatusMessage)
                    .font(.caption)
                    .foregroundStyle(viewModel.currentAIContext?.status == .failed ? .red : .secondary)
            }

            if let tagError = viewModel.tagError {
                Text(tagError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3))
        .cornerRadius(10)
    }

    @ViewBuilder
    private var aiStatusView: some View {
        if isGeneratingAITags || viewModel.currentAIContext?.status == .pending {
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.55)
                Text("AI tagging")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.currentAIContext?.status == .complete || viewModel.currentAIContext?.status == .local {
            Label("AI", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if viewModel.currentAIContext?.status == .failed {
            Label("Failed", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .help(viewModel.currentAIContext?.error ?? "AI tagging failed")
        } else if viewModel.currentAIContext?.status == .skipped {
            Label("Skipped", systemImage: "pause.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(viewModel.currentAIContext?.error ?? "AI tagging was skipped")
        }
    }

    private var visibleTagRecords: [Tag] {
        viewModel.currentTagRecords.filter { !TagVisibility.isHidden($0.name, for: viewModel.capture) }
    }

    private var hiddenTagRecords: [Tag] {
        viewModel.currentTagRecords.filter { TagVisibility.isHidden($0.name, for: viewModel.capture) }
    }

    private var aiStatusMessage: String? {
        guard let context = viewModel.currentAIContext else { return nil }
        switch context.status {
        case .local:
            return nil
        case .pending:
            return "AI tagging is running in the background."
        case .complete:
            return nil
        case .failed:
            return context.error ?? "AI tagging failed. Check Settings > AI."
        case .skipped:
            return context.error ?? "Skipped by AI rate limit."
        }
    }

    private func generateAITags() {
        guard !isGeneratingAITags else { return }
        isGeneratingAITags = true
        Task {
            await viewModel.generateAITags()
            isGeneratingAITags = false
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes").font(.headline)
                Spacer()
                if isEditingNotes {
                    Button("Done") { saveNotes() }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
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
            row("App", viewModel.capture.appName)
            row("Bundle ID", viewModel.capture.appBundleId)
            row("Window", viewModel.capture.windowTitle)
            if viewModel.capture.isScrolling, let i = viewModel.capture.scrollIndex { row("Slice", "#\(i + 1)") }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k).font(.caption).foregroundColor(.secondary).frame(width: 70, alignment: .leading)
            Text(v).font(.caption).lineLimit(2)
        }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.75), 4.0)
    }

    private func saveNotes() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await viewModel.updateCurrentNotes(trimmed)
            notes = viewModel.capture.notes ?? ""
            isEditingNotes = false
        }
    }

    private func copyCurrentImage() {
        guard let img = ImageStorageManager.shared.fullImage(for: viewModel.capture) else { return }
        ClipboardManager.shared.copyToClipboard(img)
    }

    private func copyText(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func showCurrentInFinder() {
        let path: String
        if viewModel.capture.contextType == .file,
           let filePath = viewModel.capture.filePath,
           FileManager.default.fileExists(atPath: filePath) {
            path = filePath
        } else {
            path = viewModel.capture.screenshotPath
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func addTagsFromField() {
        let names = newTag
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        newTag = ""
        Task {
            for name in names {
                await viewModel.addTag(name)
            }
        }
    }
}
