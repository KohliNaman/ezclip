import SwiftUI

struct LibraryView: View {
    @Environment(LibraryViewModel.self) private var viewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingSettings = false
    @State private var bulkTagMode: BulkTagMode?
    @State private var showingSelectionCollectionSheet = false
    @State private var keyMonitor: Any?
    @AppStorage("ezclip.libraryAppearance") private var appearance = LibraryAppearanceMode.studio.rawValue

    var body: some View {
        @Bindable var viewModel = viewModel
        Group {
            if appearance == LibraryAppearanceMode.studio.rawValue {
                StudioLibraryView()
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            VStack(spacing: 0) {
                // Top bar
                FilterBar()

                // Main content
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading captures...")
                        .scaleEffect(0.8)
                    Spacer()
                } else if viewModel.filteredCaptures.isEmpty {
                    emptyState
                } else {
                    let visibleCaptures = viewModel.filteredCaptures
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(visibleCaptures) { capture in
                                CaptureCardView(
                                    capture: capture,
                                    tags: viewModel.visibleTags(for: capture),
                                    isSelected: viewModel.selectedCaptureIDs.contains(capture.id),
                                    showsSelection: viewModel.isSelectionMode
                                )
                                    .onTapGesture {
                                        if viewModel.isSelectionMode {
                                            viewModel.toggleSelection(
                                                for: capture,
                                                in: visibleCaptures,
                                                extendRange: NSEvent.modifierFlags.contains(.shift)
                                            )
                                        } else {
                                            openDetail(for: capture)
                                        }
                                    }
                                    .contextMenu {
                                        Button("Open in Browser") {
                                            openInBrowser(capture)
                                        }
                                        .disabled(capture.url == nil)

                                        Divider()

                                        collectionMenu(for: capture)

                                        Divider()

                                        Button("Generate AI Tags") {
                                            Task { await viewModel.generateAITags(for: capture) }
                                        }

                                        Divider()

                                        Button("Show in Finder") {
                                            NSWorkspace.shared.activateFileViewerSelecting(
                                                [URL(fileURLWithPath: capture.screenshotPath)]
                                            )
                                        }

                                        Divider()

                                        Button("Delete", role: .destructive) {
                                            Task { await viewModel.deleteCapture(capture) }
                                        }
                                    }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        // Scrolling capture button (only for browsers)
                        if ExperimentalFeatures.scrollingCapture && isBrowserFrontmost() {
                            Button(action: {
                                Task { await CaptureOrchestrator.shared.captureScrolling() }
                            }) {
                                Label("Full Page", systemImage: "scroll")
                            }
                            .help("Capture scrolling screenshot")
                        }

                        if viewModel.isSelectionMode {
                            Menu {
                                Button("New Collection...") {
                                    showingSelectionCollectionSheet = true
                                }
                                Divider()
                                ForEach(viewModel.collections) { collection in
                                    Button(collection.name) {
                                        Task { await viewModel.assignSelectedCaptures(to: collection.id) }
                                    }
                                }
                                if !viewModel.collections.isEmpty {
                                    Divider()
                                }
                                Button("Remove from Collection") {
                                    Task { await viewModel.assignSelectedCaptures(to: nil) }
                                }
                            } label: {
                                Label("Add To", systemImage: "folder.badge.plus")
                            }
                            .disabled(viewModel.selectedCaptureIDs.isEmpty)

                            Menu {
                                Button("Add Tags") {
                                    bulkTagMode = .add
                                }
                                Button("Remove Tags") {
                                    bulkTagMode = .remove
                                }
                                Divider()
                                Button("Generate AI Tags") {
                                    Task { await viewModel.generateAITagsForSelectedCaptures() }
                                }
                            } label: {
                                Label("Tag", systemImage: "tag")
                            }
                            .disabled(viewModel.selectedCaptureIDs.isEmpty)

                            Button(role: .destructive) {
                                Task { await viewModel.deleteSelectedCaptures() }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(viewModel.selectedCaptureIDs.isEmpty)
                        }

                        Button {
                            if viewModel.isSelectionMode {
                                viewModel.clearSelection()
                            } else {
                                viewModel.isSelectionMode = true
                            }
                        } label: {
                            Label(viewModel.isSelectionMode ? "Cancel" : "Select", systemImage: viewModel.isSelectionMode ? "xmark" : "checkmark.circle")
                        }

                        // Sort picker
                        Picker("Sort", selection: $viewModel.sortOrder) {
                            ForEach(LibraryViewModel.SortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 90)
                    }
                }
            }
                }
            }
        }
        .task {
            await viewModel.loadAll()
        }
        .task(id: viewModel.searchText) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await viewModel.loadAll()
        }
        .onChange(of: viewModel.sortOrder) { _, _ in
            Task { await viewModel.loadAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCaptureCreated)) { _ in
            Task { await viewModel.loadAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureDeleted)) { _ in
            Task { await viewModel.loadAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureTagsChanged)) { _ in
            Task { await viewModel.loadAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureAIContextChanged)) { _ in
            Task { await viewModel.loadAll() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $bulkTagMode) { mode in
            BulkTagSheet(mode: mode, captureCount: viewModel.selectedCaptureIDs.count) { text in
                let ids = viewModel.selectedCaptureIDs
                Task {
                    switch mode {
                    case .add:
                        await viewModel.addTags(text, to: ids)
                    case .remove:
                        await viewModel.removeTags(text, from: ids)
                    }
                    bulkTagMode = nil
                }
            } onCancel: {
                bulkTagMode = nil
            }
        }
        .sheet(isPresented: $showingSelectionCollectionSheet) {
            NewCollectionForSelectionSheet(captureCount: viewModel.selectedCaptureIDs.count) { name in
                Task {
                    await viewModel.addCollectionAndAssignSelectedCaptures(name: name)
                    showingSelectionCollectionSheet = false
                }
            } onCancel: {
                showingSelectionCollectionSheet = false
            }
        }
        .onAppear {
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            installKeyMonitor()
            // Register global hotkey
            _ = HotkeyManager.shared.register {
                Task { await CaptureOrchestrator.shared.capture() }
            }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Grid

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 12)]
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(viewModel.selectedCollection == nil ? "No captures yet" : "No captures in this collection")
                .font(.title2)
                .fontWeight(.medium)

            Text(viewModel.selectedCollection == nil
                 ? "Press ⌘⌘ in any app to capture a screenshot with context."
                 : "Use Select mode or a card context menu from All Captures to add screenshots here.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if viewModel.selectedCollection == nil {
                HStack(spacing: 4) {
                    Text("⌘")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(4)
                    Text("+")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("⌘")
                        .font(.caption)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .cornerRadius(4)
                }
                .fontDesign(.monospaced)
            } else {
                Button {
                    viewModel.showAllCaptures()
                    viewModel.isSelectionMode = true
                } label: {
                    Label("Select Captures", systemImage: "checkmark.circle")
                }
            }

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func openDetail(for capture: Capture) {
        let captures = viewModel.filteredCaptures
        let index = captures.firstIndex(where: { $0.id == capture.id }) ?? 0
        DetailWindow.shared.show(captures: captures, at: index) {
            // Detail window dismissed — nothing to clean up
        }
    }

    private func openInBrowser(_ capture: Capture) {
        guard let urlStr = capture.url, let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private func collectionMenu(for capture: Capture) -> some View {
        Menu("Add to Collection") {
            if viewModel.collections.isEmpty {
                Text("No Collections")
            } else {
                ForEach(viewModel.collections) { collection in
                    Button(collection.name) {
                        Task { await viewModel.assignToCollection(capture.id, collectionId: collection.id) }
                    }
                }
            }
            if capture.collectionId != nil {
                Divider()
                Button("Remove from Collection") {
                    Task { await viewModel.assignToCollection(capture.id, collectionId: nil) }
                }
            }
        }
    }

    private func isBrowserFrontmost() -> Bool {
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return ["com.apple.Safari", "com.google.Chrome", "app.zen-browser.zen"].contains(bundleId)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "c",
                  viewModel.isSelectionMode,
                  !viewModel.selectedCaptureIDs.isEmpty else {
                return event
            }
            viewModel.copySelectedImagesToClipboard()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

private enum BulkTagMode: String, Identifiable {
    case add
    case remove

    var id: String { rawValue }
    var title: String { self == .add ? "Add Tags" : "Remove Tags" }
    var actionTitle: String { self == .add ? "Add" : "Remove" }
}

private struct BulkTagSheet: View {
    let mode: BulkTagMode
    let captureCount: Int
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var tagText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode.title)
                .font(.headline)
            Text("\(mode.actionTitle) tags for \(captureCount) selected captures.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("pricing page, sidebar nav, dense table", text: $tagText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                Button(mode.actionTitle, action: submit)
                    .keyboardShortcut(.return)
                    .disabled(LibraryViewModel.parseTagInput(tagText).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func submit() {
        let text = tagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !LibraryViewModel.parseTagInput(text).isEmpty else { return }
        onSubmit(text)
    }
}

private struct NewCollectionForSelectionSheet: View {
    let captureCount: Int
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var collectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Collection")
                .font(.headline)
            Text("Create a collection for \(captureCount) selected captures.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Collection name", text: $collectionName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                Button("Create", action: submit)
                    .keyboardShortcut(.return)
                    .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func submit() {
        let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onSubmit(name)
    }
}

// MARK: - Filter Bar

struct FilterBar: View {
    @Environment(LibraryViewModel.self) private var viewModel
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 8) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search captures...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5))
            .cornerRadius(6)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: searchText) { _, new in
            viewModel.searchText = new
        }
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let label: String
    let icon: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 3) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .medium : .regular)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.5)))
        .foregroundStyle(isSelected ? .white : .primary)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}
