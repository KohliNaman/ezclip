import Foundation
import GRDB

struct FileDeletionRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "fileDeletionQueue"

    var id: UUID
    var path: String
    var createdAt: Date
    var attemptCount: Int
    var lastError: String?
    var nextAttemptAt: Date?
}
