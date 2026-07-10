import Foundation
import GRDB

enum AITaggingStatus: String, Codable, Sendable {
    case local
    case pending
    case complete
    case failed
    case skipped
}

enum CaptureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case music
    case conversation
    case booking
    case place
    case article
    case design
    case product
    case social
    case document
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .music: "Music"
        case .conversation: "Conversations"
        case .booking: "Bookings"
        case .place: "Places"
        case .article: "Reading"
        case .design: "Design"
        case .product: "Products"
        case .social: "Social"
        case .document: "Documents"
        case .other: "Other"
        }
    }

    var iconName: String {
        switch self {
        case .music: "music.note"
        case .conversation: "message"
        case .booking: "calendar.badge.clock"
        case .place: "map"
        case .article: "book.pages"
        case .design: "paintbrush"
        case .product: "bag"
        case .social: "person.2"
        case .document: "doc.text"
        case .other: "square.grid.2x2"
        }
    }
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
    var kind: CaptureKind = .other
    var suggestedTitle: String? = nil
    var entitiesJSON: String = "{}"
    var ocrText: String? = nil
    var schemaVersion: Int = 2
    var attemptCount: Int = 0
    var nextRetryAt: Date? = nil
    var failureKind: String? = nil

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
        , kind: CaptureKind = .other
        , suggestedTitle: String? = nil
        , entitiesJSON: String = "{}"
        , ocrText: String? = nil
        , schemaVersion: Int = 2
        , attemptCount: Int = 0
        , nextRetryAt: Date? = nil
        , failureKind: String? = nil
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
        self.kind = kind
        self.suggestedTitle = suggestedTitle
        self.entitiesJSON = entitiesJSON
        self.ocrText = ocrText
        self.schemaVersion = schemaVersion
        self.attemptCount = attemptCount
        self.nextRetryAt = nextRetryAt
        self.failureKind = failureKind
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
            , kind: existing?.kind ?? .other
            , suggestedTitle: existing?.suggestedTitle
            , entitiesJSON: existing?.entitiesJSON ?? "{}"
            , ocrText: existing?.ocrText
            , attemptCount: existing?.attemptCount ?? 0
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
            , kind: existing?.kind ?? .other
            , suggestedTitle: existing?.suggestedTitle
            , entitiesJSON: existing?.entitiesJSON ?? "{}"
            , ocrText: existing?.ocrText
            , attemptCount: (existing?.attemptCount ?? 0) + 1
            , failureKind: "provider"
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
            , kind: existing?.kind ?? .other
            , suggestedTitle: existing?.suggestedTitle
            , entitiesJSON: existing?.entitiesJSON ?? "{}"
            , ocrText: existing?.ocrText
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
        static let kind = Column(CodingKeys.kind)
        static let nextRetryAt = Column(CodingKeys.nextRetryAt)
    }
}

typealias CaptureAnalysis = CaptureAIContext
