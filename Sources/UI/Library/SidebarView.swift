import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var viewModel: LibraryViewModel
    @State private var showingNewCollection = false
    @State private var newCollectionName = ""

    var body: some View {
        List(selection: $viewModel.selectedCollectionId) {
            // Quick actions
            Section {
                Label("All Captures", systemImage: "square.grid.2x2")
                    .tag(nil as UUID?)
                    .onTapGesture {
                        viewModel.selectedCollectionId = nil
                    }
            }

            // Context type groups
            Section("Context") {
                ForEach(ContextType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.iconName)
                        .tag(type.rawValue.hashValue)  // dummy tag for visual only
                        .badge(countFor(type))
                        .onTapGesture {
                            viewModel.selectedContextType = viewModel.selectedContextType == type ? nil : type
                        }
                }
            }

            // Collections
            Section("Collections") {
                ForEach(viewModel.collections) { collection in
                    Label(collection.name, systemImage: collection.icon)
                        .tag(collection.id as UUID?)
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
                    HStack {
                        Label(tag.name, systemImage: "tag")
                            .lineLimit(1)
                        Spacer()
                        Text("\(tag.usageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        viewModel.searchText = tag.name
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

                HStack {
                    Button("Cancel") {
                        showingNewCollection = false
                        newCollectionName = ""
                    }
                    .keyboardShortcut(.escape)

                    Button("Create") {
                        Task {
                            await viewModel.addCollection(name: newCollectionName)
                            showingNewCollection = false
                            newCollectionName = ""
                        }
                    }
                    .keyboardShortcut(.return)
                    .disabled(newCollectionName.isEmpty)
                }
            }
            .padding(30)
            .frame(width: 300, height: 180)
        }
    }

    private func countFor(_ type: ContextType) -> Int {
        viewModel.captures.filter { $0.contextType == type }.count
    }
}
