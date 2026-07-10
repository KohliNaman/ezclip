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
    var contentHash: String? = nil
    var storageStatus: String? = "ready"
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
    var designContextJSON: String? = nil
    var designContextStatus: String? = nil
    var designContextMessage: String? = nil
    var designContextSource: String? = nil
    var designContextUpdatedAt: Date? = nil

    // Context lifecycle
    var contextStatus: String? = "pending"

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
        timestamp.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}

extension Capture: TableRecord, FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let contextType = Column(CodingKeys.contextType)
        static let appName = Column(CodingKeys.appName)
        static let isScrolling = Column(CodingKeys.isScrolling)
        static let parentCaptureId = Column(CodingKeys.parentCaptureId)
        static let collectionId = Column(CodingKeys.collectionId)
        static let contextStatus = Column(CodingKeys.contextStatus)
        static let designContextStatus = Column(CodingKeys.designContextStatus)
        static let contentHash = Column(CodingKeys.contentHash)
        static let storageStatus = Column(CodingKeys.storageStatus)
    }
}

extension Capture {
    var designEnrichmentStatus: BrowserDesignEnrichmentStatus? {
        guard let designContextStatus else { return nil }
        return BrowserDesignEnrichmentStatus(rawValue: designContextStatus)
    }
}
