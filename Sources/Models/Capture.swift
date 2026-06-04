import Foundation
import GRDB

struct Capture: Identifiable, Codable, @unchecked Sendable {
    var id: UUID
    var timestamp: Date
    var appName: String
    var appBundleId: String
    var windowTitle: String
    var screenshotPath: String
    var thumbnailPath: String
    var contextType: ContextType

    // Website context
    var url: String?
    var pageTitle: String?
    var faviconPath: String?

    // Music context
    var songName: String?
    var artistName: String?
    var albumName: String?
    var albumArtPath: String?

    // Design context
    var designFileName: String?
    var designPageName: String?

    // File context
    var filePath: String?

    // User metadata
    var notes: String?
    var collectionId: UUID?

    // Scrolling screenshot
    var isScrolling: Bool
    var scrollIndex: Int?
    var parentCaptureId: UUID?

    // MARK: - Computed
    var contextDescription: String {
        switch contextType {
        case .website:
            pageTitle ?? url ?? windowTitle
        case .music:
            if let song = songName, let artist = artistName {
                "\(song) — \(artist)"
            } else {
                songName ?? windowTitle
            }
        case .design:
            designFileName ?? windowTitle
        case .file:
            filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? windowTitle
        case .generic:
            windowTitle
        }
    }

    var displayDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

extension Capture: TableRecord, FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let appName = Column(CodingKeys.appName)
        static let appBundleId = Column(CodingKeys.appBundleId)
        static let windowTitle = Column(CodingKeys.windowTitle)
        static let screenshotPath = Column(CodingKeys.screenshotPath)
        static let thumbnailPath = Column(CodingKeys.thumbnailPath)
        static let contextType = Column(CodingKeys.contextType)
        static let url = Column(CodingKeys.url)
        static let pageTitle = Column(CodingKeys.pageTitle)
        static let faviconPath = Column(CodingKeys.faviconPath)
        static let songName = Column(CodingKeys.songName)
        static let artistName = Column(CodingKeys.artistName)
        static let albumName = Column(CodingKeys.albumName)
        static let albumArtPath = Column(CodingKeys.albumArtPath)
        static let designFileName = Column(CodingKeys.designFileName)
        static let designPageName = Column(CodingKeys.designPageName)
        static let filePath = Column(CodingKeys.filePath)
        static let notes = Column(CodingKeys.notes)
        static let collectionId = Column(CodingKeys.collectionId)
        static let isScrolling = Column(CodingKeys.isScrolling)
        static let scrollIndex = Column(CodingKeys.scrollIndex)
        static let parentCaptureId = Column(CodingKeys.parentCaptureId)
    }

    nonisolated(unsafe) static let tags = hasMany(
        Tag.self,
        through: CaptureTag.self,
        using: CaptureTag.capture
    )
}
