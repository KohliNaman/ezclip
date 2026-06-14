import SwiftUI

private final class ThumbnailLoadResult: @unchecked Sendable {
    let image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }
}

struct CaptureCardView: View {
    let capture: Capture
    var isSelected: Bool = false
    var showsSelection: Bool = false
    @State private var thumbnail: NSImage?
    @State private var didFinishLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if didFinishLoading {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 22))
                                Text("Missing File")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                }

                // Scrolling badge
                if capture.isScrolling {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 2) {
                                Image(systemName: "scroll")
                                    .font(.system(size: 8))
                                Text("FULL PAGE")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding(4)
                        }
                        Spacer()
                    }
                }

                if showsSelection {
                    VStack {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(isSelected ? Color.white : Color.secondary, isSelected ? Color.accentColor : Color.clear)
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 140)
            .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Context badge
                HStack(spacing: 4) {
                    Image(systemName: capture.contextType.iconName)
                        .font(.system(size: 9))
                    Text(capture.contextDescription)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.5))
                .cornerRadius(3)

                // App + time
                HStack {
                    Text(capture.appName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(capture.displayDate)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .task(id: capture.id) {
            thumbnail = nil
            didFinishLoading = false
            let result = await Task.detached(priority: .utility) {
                ThumbnailLoadResult(image: ImageStorageManager.shared.thumbnailImage(for: capture))
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = result.image
            didFinishLoading = true
        }
        .onDisappear {
            thumbnail = nil
            didFinishLoading = false
        }
    }
}
