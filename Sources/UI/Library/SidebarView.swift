import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @State private var showingNewCollection = false
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
            Section("Tags") {
                ForEach(viewModel.tags.prefix(15)) { tag in
                    sidebarButton(
                        title: tag.name,
                        icon: "tag",
                        count: tag.usageCount,
                        isSelected: viewModel.selectedTagName == tag.name
                    ) {
                        viewModel.selectTag(tag.name)
                    }
                }

                if viewModel.tags.count > 15 {
                    Text("+\(viewModel.tags.count - 15) more tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
}
