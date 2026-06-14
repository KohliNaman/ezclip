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
    @State private var selectedTag: Tag?
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

            List(viewModel.tags, selection: $selectedTag) { tag in
                HStack {
                    Label(tag.name, systemImage: "tag")
                    Spacer()
                    Text("\(tag.usageCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .tag(tag)
            }
            .frame(minHeight: 280)

            if let selectedTag {
                HStack {
                    TextField("Rename tag", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { renameText = selectedTag.name }
                        .onChange(of: selectedTag.id) { _, _ in renameText = selectedTag.name }
                    Button("Rename") {
                        Task { await viewModel.renameTag(selectedTag, to: renameText) }
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Menu("Merge") {
                        ForEach(viewModel.tags.filter { $0.id != selectedTag.id }) { destination in
                            Button(destination.name) {
                                Task {
                                    await viewModel.mergeTag(selectedTag, into: destination)
                                    self.selectedTag = destination
                                }
                            }
                        }
                    }
                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.deleteTag(selectedTag)
                            self.selectedTag = nil
                            renameText = ""
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 430)
    }
}
