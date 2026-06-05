import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showingSettings = false

    var body: some View {
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
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(viewModel.filteredCaptures) { capture in
                                CaptureCardView(capture: capture)
                                    .onTapGesture {
                                        viewModel.selectedCapture = capture
                                    }
                                    .contextMenu {
                                        Button("Open in Browser") {
                                            openInBrowser(capture)
                                        }
                                        .disabled(capture.url == nil)

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
            .popover(item: $viewModel.selectedCapture) { capture in
                CaptureDetailView(capture: capture)
                    .frame(minWidth: 700, idealWidth: 800, minHeight: 600)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 4) {
                        // Scrolling capture button (only for browsers)
                        if isBrowserFrontmost() {
                            Button(action: {
                                Task { await CaptureOrchestrator.shared.captureScrolling() }
                            }) {
                                Label("Full Page", systemImage: "scroll")
                            }
                            .help("Capture scrolling screenshot")
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
        .task {
            await viewModel.loadAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCaptureCreated)) { _ in
            Task { await viewModel.loadAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureDeleted)) { _ in
            Task { await viewModel.loadAll() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onAppear {
            // Register global hotkey
            HotkeyManager.shared.register {
                Task { await CaptureOrchestrator.shared.capture() }
            }
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

            Text("No captures yet")
                .font(.title2)
                .fontWeight(.medium)

            Text("Press ⌘⌘ in any app to capture a screenshot with context.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

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

            Spacer()
        }
        .padding(32)
    }

    // MARK: - Helpers

    private func openInBrowser(_ capture: Capture) {
        guard let urlStr = capture.url, let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }

    private func isBrowserFrontmost() -> Bool {
        guard let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return ["com.apple.Safari", "com.google.Chrome", "app.zen-browser.zen"].contains(bundleId)
    }
}

// MARK: - Filter Bar

struct FilterBar: View {
    @EnvironmentObject var viewModel: LibraryViewModel
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

            Divider()
                .frame(height: 20)

            // Context type filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    FilterPill(
                        label: "All",
                        icon: nil,
                        isSelected: viewModel.selectedContextType == nil
                    ).onTapGesture {
                        viewModel.selectedContextType = nil
                    }

                    ForEach(ContextType.allCases, id: \.self) { type in
                        FilterPill(
                            label: type.displayName,
                            icon: type.iconName,
                            isSelected: viewModel.selectedContextType == type
                        ).onTapGesture {
                            viewModel.selectedContextType = viewModel.selectedContextType == type ? nil : type
                        }
                    }
                }
            }

            Spacer()

            // Caption count
            Text("\(viewModel.filteredCaptures.count) captures")
                .font(.caption)
                .foregroundColor(.secondary)
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
