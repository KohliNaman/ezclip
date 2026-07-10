import Foundation
import GRDB

struct CanvasPlacement: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "canvasPlacement"

    var boardKey: String
    var captureId: UUID
    var x: Double
    var y: Double
    var zIndex: Int
    var scale: Double

    var id: String { "\(boardKey):\(captureId.uuidString)" }
}
