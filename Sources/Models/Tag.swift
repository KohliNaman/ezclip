import Foundation
import GRDB

struct Tag: Identifiable, Codable {
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

    static let captures = hasMany(
        Capture.self,
        through: CaptureTag.self,
        using: CaptureTag.tag
    )
}

// MARK: - Join table

struct CaptureTag: Codable {
    var captureId: UUID
    var tagId: UUID

    static let capture = belongsTo(Capture.self)
    static let tag = belongsTo(Tag.self)
}

extension CaptureTag: TableRecord, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "captureTag"
}
