import Foundation
import GRDB

struct Collection: Identifiable, Codable, @unchecked Sendable {
    var id: UUID
    var name: String
    var color: String
    var icon: String
    var sortOrder: Int

    var collectionSymbol: TagSymbol {
        if let symbol = TagSymbol(storageValue: icon) { return symbol }
        if PhosphorTagIcon(rawValue: icon) != nil {
            return TagSymbol(kind: .phosphor, value: icon)
        }
        switch icon {
        case "folder":
            return TagSymbol(kind: .phosphor, value: PhosphorTagIcon.folder.rawValue)
        default:
            return TagSymbol(kind: .emoji, value: "📁")
        }
    }
}

extension Collection: TableRecord, FetchableRecord, MutablePersistableRecord {
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let name = Column(CodingKeys.name)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }
}
