import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum LibraryAppearanceMode: String, CaseIterable, Identifiable {
    case studio
    case classic

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

private enum StudioLayoutMode: String, CaseIterable, Identifiable {
    case wall
    case canvas
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

struct StudioLibraryView: View {
    @Environment(LibraryViewModel.self) private var viewModel
    @AppStorage("ezclip.studio.density") private var density = 0.55
    @State private var layoutMode: StudioLayoutMode = .wall
    @State private var showingImporter = false

    var body: some View {
        @Bindable var viewModel = viewModel
        HStack(spacing: 0) {
            studioSidebar.frame(width: 216)
            Divider()
            VStack(spacing: 0) {
                toolbar
                Divider()
                if layoutMode == .wall { wall } else { StudioCanvasView(boardKey: boardKey) }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.image], allowsMultipleSelection: true, onCompletion: importSelection)
        .dropDestination(for: URL.self) { urls, _ in importURLs(urls); return true }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your library", text: Bindable(viewModel).searchText).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).frame(width: 320, height: 32)
            .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 6))
            Picker("View", selection: $layoutMode) {
                ForEach(StudioLayoutMode.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 150)
            Spacer()
            Text("Density").font(.caption).foregroundStyle(.secondary)
            Slider(value: $density, in: 0...1).frame(width: 90)
            Text("\(viewModel.captures.count) items")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .trailing)
            Button { showingImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                .help("Import screenshots")
            Button {
                viewModel.isSelectionMode.toggle()
                if !viewModel.isSelectionMode { viewModel.clearSelection() }
            } label: { Image(systemName: viewModel.isSelectionMode ? "xmark" : "checkmark.circle") }
                .help(viewModel.isSelectionMode ? "Cancel selection" : "Select captures")
        }
        .buttonStyle(.borderless).padding(.horizontal, 14).frame(height: 48)
    }

    private var studioSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.green)
                Text("ezclip").font(.headline)
            }
            .padding(.horizontal, 14).frame(height: 48)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    sidebarLabel("Smart Views")
                    sidebarButton("All items", icon: "square.grid.2x2", selected: viewModel.selectedCaptureKind == nil && viewModel.selectedCollectionId == nil) {
                        viewModel.showAllCaptures(); Task { await viewModel.loadAll() }
                    }
                    ForEach(CaptureKind.allCases.filter { $0 != .other }) { kind in
                        sidebarButton(kind.displayName, icon: kind.iconName, selected: viewModel.selectedCaptureKind == kind) {
                            viewModel.selectCaptureKind(kind)
                        }
                    }
                    Divider().padding(.vertical, 8)
                    sidebarLabel("Collections")
                    ForEach(viewModel.collections) { collection in
                        Button { viewModel.selectCollection(collection.id) } label: {
                            HStack(spacing: 8) {
                                TagSymbolView(symbol: collection.collectionSymbol, size: 14)
                                Text(collection.name).lineLimit(1)
                                Spacer()
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(StudioSidebarButtonStyle(selected: viewModel.selectedCollectionId == collection.id))
                    }
                }.padding(10)
            }
            Button { showingImporter = true } label: {
                Label("Import screenshots", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).padding(14)
        }
        .background(.ultraThinMaterial)
    }

    private var wall: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(viewModel.filteredCaptures) { capture in
                    StudioCaptureTile(
                        capture: capture,
                        analysis: viewModel.aiContextsByCaptureID[capture.id],
                        selected: viewModel.selectedCaptureIDs.contains(capture.id),
                        selectionMode: viewModel.isSelectionMode
                    ) {
                        if viewModel.isSelectionMode {
                            viewModel.toggleSelection(for: capture, in: viewModel.filteredCaptures)
                        } else { openDetail(capture) }
                    }
                    .onAppear {
                        if capture.id == viewModel.filteredCaptures.last?.id { Task { await viewModel.loadNextPage() } }
                    }
                }
            }.padding(12)
            if viewModel.isLoadingNextPage { ProgressView().padding() }
        }
    }

    private var columns: [GridItem] {
        let minimum = 170 + density * 110
        return [GridItem(.adaptive(minimum: minimum, maximum: minimum + 70), spacing: 10)]
    }
    private var boardKey: String { viewModel.selectedCollectionId?.uuidString ?? "global" }

    private func sidebarLabel(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            .padding(.horizontal, 7).padding(.top, 8)
    }
    private func sidebarButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
            .buttonStyle(StudioSidebarButtonStyle(selected: selected))
    }
    private func openDetail(_ capture: Capture) {
        guard let index = viewModel.filteredCaptures.firstIndex(where: { $0.id == capture.id }) else { return }
        DetailWindow.shared.show(captures: viewModel.filteredCaptures, at: index) { viewModel.selectedCapture = nil }
    }
    private func importSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }; importURLs(urls)
    }
    private func importURLs(_ urls: [URL]) {
        Task {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            _ = await CaptureImportService.shared.importFiles(urls)
            await viewModel.loadAll()
        }
    }
}

private struct StudioSidebarButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12.5, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 8).frame(height: 30)
            .foregroundStyle(selected ? .primary : .secondary)
            .background(selected ? Color.primary.opacity(0.09) : Color.clear, in: .rect(cornerRadius: 5))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct StudioCaptureTile: View {
    let capture: Capture
    let analysis: CaptureAIContext?
    let selected: Bool
    let selectionMode: Bool
    let action: () -> Void
    @State private var thumbnail: NSImage?
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                        else { Rectangle().fill(.quaternary); ProgressView().controlSize(.small) }
                    }
                    .frame(maxWidth: .infinity).aspectRatio(4 / 3, contentMode: .fit).clipped()
                    if selectionMode || hovered {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3).symbolRenderingMode(.hierarchical).padding(7)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(analysis?.suggestedTitle ?? capture.contextDescription).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    HStack {
                        Label((analysis?.kind ?? .other).displayName, systemImage: (analysis?.kind ?? .other).iconName)
                        Spacer(); Text(capture.displayDate)
                    }.font(.system(size: 9.5)).foregroundStyle(.secondary)
                }.padding(8)
            }
            .background(.background).clipShape(.rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.green : Color.primary.opacity(hovered ? 0.22 : 0.09), lineWidth: selected ? 2 : 1) }
            .shadow(color: .black.opacity(hovered ? 0.13 : 0.05), radius: hovered ? 9 : 3, y: hovered ? 4 : 1)
            .scaleEffect(hovered ? 1.012 : 1)
        }
        .buttonStyle(.plain).onHover { hovered = $0 }.animation(.snappy(duration: 0.18), value: hovered)
        .task(id: capture.id) { thumbnail = await Task.detached(priority: .utility) { ImageStorageManager.shared.thumbnailImage(for: capture) }.value }
        .onDisappear { thumbnail = nil }
    }
}

private struct StudioCanvasView: View {
    @Environment(LibraryViewModel.self) private var viewModel
    let boardKey: String
    @State private var placements: [UUID: CanvasPlacement] = [:]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(nsColor: .controlBackgroundColor)).frame(width: 2400, height: 1600)
                ForEach(viewModel.captures.filter { placements[$0.id] != nil }) { capture in
                    if let placement = placements[capture.id] {
                        CanvasCaptureItem(capture: capture, placement: placement) { point in
                            var updated = placement; updated.x = point.x; updated.y = point.y
                            placements[capture.id] = updated
                            Task { try? await DatabaseManager.shared.saveCanvasPlacement(updated) }
                        }
                        .position(x: placement.x, y: placement.y).zIndex(Double(placement.zIndex))
                    }
                }
            }
        }
        .overlay {
            if placements.isEmpty {
                ContentUnavailableView {
                    Label("Empty canvas", systemImage: "rectangle.3.group")
                } description: { Text("Arrange the current page into a spatial board.") }
                actions: { Button("Arrange Current Page", action: arrangeCurrentPage) }
            }
        }
        .task(id: boardKey) {
            let values = (try? await DatabaseManager.shared.canvasPlacements(boardKey: boardKey)) ?? []
            placements = Dictionary(uniqueKeysWithValues: values.map { ($0.captureId, $0) })
        }
    }

    private func arrangeCurrentPage() {
        for (index, capture) in viewModel.captures.prefix(40).enumerated() {
            let placement = CanvasPlacement(boardKey: boardKey, captureId: capture.id,
                x: 150 + Double((index % 6) * 310), y: 125 + Double((index / 6) * 245), zIndex: index, scale: 1)
            placements[capture.id] = placement
            Task { try? await DatabaseManager.shared.saveCanvasPlacement(placement) }
        }
    }
}

private struct CanvasCaptureItem: View {
    let capture: Capture
    let placement: CanvasPlacement
    let onMove: (CGPoint) -> Void
    @State private var thumbnail: NSImage?
    @State private var translation: CGSize = .zero

    var body: some View {
        Group {
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
            else { Rectangle().fill(.quaternary) }
        }
        .frame(width: 260, height: 180).clipShape(.rect(cornerRadius: 5))
        .overlay(alignment: .bottomLeading) {
            Text(capture.contextDescription).font(.caption.weight(.medium)).lineLimit(1)
                .padding(7).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 5).offset(translation)
        .gesture(DragGesture().onChanged { translation = $0.translation }.onEnded {
            onMove(CGPoint(x: placement.x + $0.translation.width, y: placement.y + $0.translation.height)); translation = .zero
        })
        .task { thumbnail = await Task.detached { ImageStorageManager.shared.thumbnailImage(for: capture) }.value }
    }
}
