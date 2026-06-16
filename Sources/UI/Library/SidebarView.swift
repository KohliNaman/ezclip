import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @State private var showingNewCollection = false
    @State private var showingTagManager = false
    @State private var tagToRename: Tag?
    @State private var tagRenameText = ""
    @State private var newCollectionName = ""

    var body: some View {
        List {
            // Quick actions
            Section {
                sidebarButton(
                    title: "All Captures",
                    icon: "square.grid.2x2",
                    count: viewModel.totalCapturesCount,
                    isSelected: viewModel.selectedContextType == nil
                        && viewModel.selectedCollectionId == nil
                        && viewModel.selectedTagName == nil
                ) {
                    viewModel.showAllCaptures()
                }
            }

            // Context type groups
            Section("Context") {
                ForEach(ContextType.allCases, id: \.self) { type in
                    sidebarButton(
                        title: type.displayName,
                        icon: type.iconName,
                        count: countFor(type),
                        isSelected: viewModel.selectedContextType == type
                    ) {
                        viewModel.selectContextType(type)
                    }
                }
            }

            // Collections
            Section("Collections") {
                ForEach(viewModel.collections) { collection in
                    sidebarButton(
                        title: collection.name,
                        icon: collection.icon,
                        count: nil,
                        isSelected: viewModel.selectedCollectionId == collection.id
                    ) {
                        viewModel.selectCollection(collection.id)
                    }
                }

                Button(action: { showingNewCollection = true }) {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // Popular tags
            Section {
                ForEach(viewModel.tags.prefix(15)) { tag in
                    sidebarButton(
                        title: tag.name,
                        icon: "tag",
                        count: tag.usageCount,
                        isSelected: viewModel.selectedTagName == tag.name
                    ) {
                        viewModel.selectTag(tag.name)
                    }
                    .contextMenu {
                        Button("Rename") {
                            tagToRename = tag
                            tagRenameText = tag.name
                        }
                        Menu("Merge Into") {
                            ForEach(viewModel.tags.filter { $0.id != tag.id }) { destination in
                                Button(destination.name) {
                                    Task { await viewModel.mergeTag(tag, into: destination) }
                                }
                            }
                        }
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.deleteTag(tag) }
                        }
                    }
                }

                if viewModel.tags.count > 15 {
                    Text("+\(viewModel.tags.count - 15) more tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Tags")
                    Spacer()
                    Button("Manage") { showingTagManager = true }
                        .font(.caption2)
                        .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showingNewCollection) {
            VStack(spacing: 16) {
                Text("New Collection")
                    .font(.headline)

                TextField("Collection name", text: $newCollectionName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
                    .onSubmit { createCollection() }

                HStack {
                    Button("Cancel") {
                        showingNewCollection = false
                        newCollectionName = ""
                    }
                    .keyboardShortcut(.escape)

                    Button("Create") {
                        createCollection()
                    }
                    .keyboardShortcut(.return)
                    .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(30)
            .frame(width: 300, height: 180)
        }
        .sheet(item: $tagToRename) { tag in
            VStack(spacing: 16) {
                Text("Rename Tag")
                    .font(.headline)
                TextField("Tag name", text: $tagRenameText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { rename(tag) }
                HStack {
                    Button("Cancel") { tagToRename = nil }
                        .keyboardShortcut(.escape)
                    Button("Rename") { rename(tag) }
                        .keyboardShortcut(.return)
                        .disabled(tagRenameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(26)
            .frame(width: 340, height: 170)
        }
        .sheet(isPresented: $showingTagManager) {
            TagManagementView()
                .environmentObject(viewModel)
        }
    }

    private func countFor(_ type: ContextType) -> Int {
        viewModel.captures.filter { $0.contextType == type }.count
    }

    private func sidebarButton(
        title: String,
        icon: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await viewModel.addCollection(name: name)
            showingNewCollection = false
            newCollectionName = ""
        }
    }

    private func rename(_ tag: Tag) {
        let name = tagRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await viewModel.renameTag(tag, to: name)
            tagToRename = nil
            tagRenameText = ""
        }
    }
}

private struct TagManagementView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTagIDs: Set<Tag.ID> = []
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Manage Tags")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
            }

            Text("Use Command-click or Shift-click to select multiple tags.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(viewModel.tags, selection: $selectedTagIDs) { tag in
                HStack {
                    Label(tag.name, systemImage: "tag")
                    Spacer()
                    Text("\(tag.usageCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(tag.id)
            }
            .frame(minHeight: 280)
            .onChange(of: selectedTagIDs) { _, _ in
                renameText = singleSelectedTag?.name ?? ""
            }

            if let selectedTag = singleSelectedTag {
                HStack {
                    TextField("Rename tag", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                    Button("Rename") {
                        Task {
                            await viewModel.renameTag(selectedTag, to: renameText)
                            selectedTagIDs = []
                            renameText = ""
                        }
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.deleteTag(selectedTag)
                            selectedTagIDs = []
                            renameText = ""
                        }
                    }
                }
            }

            if selectedTagIDs.count > 1 {
                HStack {
                    Text("\(selectedTagIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Menu("Merge Selected") {
                        ForEach(selectedTags) { destination in
                            Button("Into \(destination.name)") {
                                Task {
                                    for source in selectedTags where source.id != destination.id {
                                        await viewModel.mergeTag(source, into: destination)
                                    }
                                    selectedTagIDs = [destination.id]
                                    renameText = destination.name
                                }
                            }
                        }
                    }
                    Button("Delete Selected", role: .destructive) {
                        Task {
                            for tag in selectedTags {
                                await viewModel.deleteTag(tag)
                            }
                            selectedTagIDs = []
                            renameText = ""
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 430)
    }

    private var selectedTags: [Tag] {
        viewModel.tags.filter { selectedTagIDs.contains($0.id) }
    }

    private var singleSelectedTag: Tag? {
        guard selectedTagIDs.count == 1, let id = selectedTagIDs.first else { return nil }
        return viewModel.tags.first { $0.id == id }
    }
}
