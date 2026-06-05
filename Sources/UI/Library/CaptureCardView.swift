import SwiftUI

struct CaptureCardView: View {
    let capture: Capture
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        .onAppear {
            thumbnail = ImageStorageManager.shared.thumbnailImage(for: capture)
        }
    }
}
