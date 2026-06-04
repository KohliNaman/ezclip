import Foundation
import GRDB

struct Collection: Identifiable, Codable, @unchecked Sendable {
    var id: UUID
    var name: String
    var color: String
    var icon: String
    var sortOrder: Int
}

extension Collection: TableRecord, FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }
}
