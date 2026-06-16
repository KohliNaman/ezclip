import Foundation
import GRDB

enum AITaggingStatus: String, Codable, Sendable {
    case pending
    case complete
    case failed
    case skipped
}

struct CaptureAIContext: Identifiable, Codable, Hashable, @unchecked Sendable {
    var captureId: UUID
    var visibleTagsJSON: String
    var hiddenSearchTagsJSON: String
    var summary: String?
    var provider: String
    var model: String
    var status: AITaggingStatus
    var error: String?
    var confidence: Double?
    var createdAt: Date
    var updatedAt: Date

    var id: UUID { captureId }

    var visibleTags: [String] {
        Self.decodeTags(visibleTagsJSON)
    }

    var hiddenSearchTags: [String] {
        Self.decodeTags(hiddenSearchTagsJSON)
    }

    init(
        captureId: UUID,
        visibleTags: [String],
        hiddenSearchTags: [String],
        summary: String?,
        provider: String,
        model: String,
        status: AITaggingStatus,
        error: String? = nil,
        confidence: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.captureId = captureId
        self.visibleTagsJSON = Self.encodeTags(visibleTags)
        self.hiddenSearchTagsJSON = Self.encodeTags(hiddenSearchTags)
        self.summary = summary
        self.provider = provider
        self.model = model
        self.status = status
        self.error = error
        self.confidence = confidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func pending(captureId: UUID, provider: String, model: String, existing: CaptureAIContext?) -> CaptureAIContext {
        let now = Date()
        return CaptureAIContext(
            captureId: captureId,
            visibleTags: existing?.visibleTags ?? [],
            hiddenSearchTags: existing?.hiddenSearchTags ?? [],
            summary: existing?.summary,
            provider: provider,
            model: model,
            status: .pending,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    static func failed(captureId: UUID, provider: String, model: String, message: String, existing: CaptureAIContext?) -> CaptureAIContext {
        let now = Date()
        return CaptureAIContext(
            captureId: captureId,
            visibleTags: existing?.visibleTags ?? [],
            hiddenSearchTags: existing?.hiddenSearchTags ?? [],
            summary: existing?.summary,
            provider: provider,
            model: model,
            status: .failed,
            error: message,
            confidence: existing?.confidence,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    static func skipped(captureId: UUID, provider: String, model: String, message: String, existing: CaptureAIContext?) -> CaptureAIContext {
        let now = Date()
        return CaptureAIContext(
            captureId: captureId,
            visibleTags: existing?.visibleTags ?? [],
            hiddenSearchTags: existing?.hiddenSearchTags ?? [],
            summary: existing?.summary,
            provider: provider,
            model: model,
            status: .skipped,
            error: message,
            confidence: existing?.confidence,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    static func encodeTags(_ tags: [String]) -> String {
        let normalized = DatabaseManager.normalizedTagNames(tags)
        guard let data = try? JSONEncoder().encode(normalized),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    static func decodeTags(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return DatabaseManager.normalizedTagNames(tags)
    }
}

extension CaptureAIContext: TableRecord, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "captureAIContext"

    enum Columns {
        static let captureId = Column(CodingKeys.captureId)
        static let status = Column(CodingKeys.status)
        static let provider = Column(CodingKeys.provider)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
