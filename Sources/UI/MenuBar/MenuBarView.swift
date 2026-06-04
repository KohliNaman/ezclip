import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var viewModel: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("ezclip")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("Settings...") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    Divider()
                    Button("Quit ezclip") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // Recent captures
            if viewModel.captures.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Press ⌘⌘ to capture")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.captures.prefix(10)) { capture in
                            HStack(spacing: 8) {
                                if let thumb = ImageStorageManager.shared.thumbnailImage(for: capture) {
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 30)
                                        .cornerRadius(4)
                                        .clipped()
                                } else {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(.quaternary)
                                        .frame(width: 40, height: 30)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(capture.contextDescription)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Text(capture.appName)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedCapture = capture
                                NSApp.activate(ignoringOtherApps: true)
                                // Bring main window to front
                                if let window = NSApp.windows.first(where: { $0.title.contains("ezclip") }) {
                                    window.makeKeyAndOrderFront(nil)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: min(CGFloat(viewModel.captures.count * 44), 300))
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Open Library") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title.contains("ezclip") }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)

                Spacer()

                Text("\(viewModel.captures.count) captures")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .task {
            await viewModel.loadAll()
        }
    }
}
