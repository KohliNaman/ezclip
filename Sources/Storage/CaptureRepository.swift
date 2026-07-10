import Foundation
import GRDB

@MainActor
final class CaptureRepository {
    static let shared = CaptureRepository()

    private let db = DatabaseManager.shared

    private init() {}

    func insert(_ capture: Capture) async throws {
        try await db.write { db in
            var mutable = capture
            try mutable.insert(db)
        }
        try await db.rebuildSearchDocument(captureId: capture.id)
    }

    func updateContext(
        captureId: UUID,
        context: ResolvedContext,
        faviconPath: String?,
        albumArtPath: String?
    ) async throws -> Capture? {
        let updated: Capture? = try await db.write { db in
            guard var capture = try Capture.fetchOne(db, key: captureId) else { return nil }

            capture.contextType = context.contextType
            capture.url = context.url
            capture.pageTitle = context.pageTitle
            capture.faviconPath = faviconPath
            capture.songName = context.songName
            capture.artistName = context.artistName
            capture.albumName = context.albumName
            capture.albumArtPath = albumArtPath
            capture.designFileName = context.designFileName
            capture.designPageName = context.designPageName
            if let designContextJSON = context.designContextJSON {
                capture.designContextJSON = designContextJSON
            }
            capture.designContextStatus = context.designContextStatus?.rawValue
            capture.designContextMessage = context.designContextMessage
            capture.designContextSource = context.designContextSource
            capture.designContextUpdatedAt = context.designContextUpdatedAt
            capture.filePath = context.filePath
            capture.contextStatus = "resolved"

            try capture.update(db)
            return capture
        }
        if let updated { try await db.rebuildSearchDocument(captureId: updated.id) }
        return updated
    }

    func markContextFailed(captureId: UUID) async throws {
        try await db.write { db in
            guard var capture = try Capture.fetchOne(db, key: captureId) else { return }
            capture.contextStatus = "failed"
            try capture.update(db)
        }
    }

    func replaceTags(for capture: Capture, names: [String]) async throws {
        _ = try await db.write { db in
            try CaptureTag
                .filter(Column("captureId") == capture.id.uuidString)
                .deleteAll(db)
        }

        guard !names.isEmpty else { return }
        let tags = try await db.ensureTagsExist(names)
        try await db.linkTags(tags.map(\.id), to: capture.id)
    }
}
