import Foundation
import GRDB

struct Tag: Identifiable, Codable, @unchecked Sendable {
    var id: UUID
    var name: String
    var usageCount: Int
}

extension Tag: TableRecord, FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let usageCount = Column(CodingKeys.usageCount)
    }
}

// MARK: - Join table

struct CaptureTag: Codable, @unchecked Sendable {
    var captureId: UUID
    var tagId: UUID

    nonisolated(unsafe) static let capture = belongsTo(Capture.self)
    nonisolated(unsafe) static let tag = belongsTo(Tag.self)
}

extension CaptureTag: TableRecord, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "captureTag"
}
