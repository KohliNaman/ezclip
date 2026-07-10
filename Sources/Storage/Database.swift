import Foundation
import GRDB

enum TaggingDatabaseError: LocalizedError {
    case captureMissing

    var errorDescription: String? {
        switch self {
        case .captureMissing:
            "This capture is no longer in the library. Close and reopen the detail view, then try tagging again."
        }
    }
}

@MainActor
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var dbQueue: DatabaseQueue?

    private init() {}

    // MARK: - Setup

    func setup() throws {
        if dbQueue != nil { return }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let ezclipDir = appSupport.appendingPathComponent("ezclip")
        try FileManager.default.createDirectory(at: ezclipDir, withIntermediateDirectories: true)

        let dbPath = ezclipDir.appendingPathComponent("ezclip.sqlite").path
        let queue = try DatabaseQueue(path: dbPath)
        try migrator.migrate(queue)
        dbQueue = queue
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "capture") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("appName", .text).notNull()
                t.column("appBundleId", .text).notNull()
                t.column("windowTitle", .text).notNull()
                t.column("screenshotPath", .text).notNull()
                t.column("thumbnailPath", .text).notNull()
                t.column("contextType", .text).notNull()
                t.column("url", .text)
                t.column("pageTitle", .text)
                t.column("faviconPath", .text)
                t.column("songName", .text)
                t.column("artistName", .text)
                t.column("albumName", .text)
                t.column("albumArtPath", .text)
                t.column("designFileName", .text)
                t.column("designPageName", .text)
                t.column("filePath", .text)
                t.column("notes", .text)
                t.column("collectionId", .text)
                t.column("isScrolling", .boolean).notNull().defaults(to: false)
                t.column("scrollIndex", .integer)
                t.column("parentCaptureId", .text)
            }

            try db.create(table: "collection") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("icon", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "tag") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
                t.column("usageCount", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "captureTag") { t in
                t.column("captureId", .text).notNull().references("capture")
                t.column("tagId", .text).notNull().references("tag")
                t.primaryKey(["captureId", "tagId"])
            }

            // Indexes for common queries
            try db.create(index: "idx_capture_timestamp", on: "capture", columns: ["timestamp"])
            try db.create(index: "idx_capture_contextType", on: "capture", columns: ["contextType"])
            try db.create(index: "idx_capture_appName", on: "capture", columns: ["appName"])
            try db.create(index: "idx_tag_name", on: "tag", columns: ["name"])
        }

        migrator.registerMigration("v2_capture_context_updates") { db in
            let existing = try Set(db.columns(in: "capture").map(\.name))
            if !existing.contains("designContextJSON") {
                try db.alter(table: "capture") { t in
                    t.add(column: "designContextJSON", .text)
                }
            }
            if !existing.contains("contextStatus") {
                try db.alter(table: "capture") { t in
                    t.add(column: "contextStatus", .text).defaults(to: "pending")
                }
            }
        }

        migrator.registerMigration("v3_ai_tagging_context") { db in
            try db.create(table: "captureAIContext", ifNotExists: true) { t in
                t.column("captureId", .text)
                    .primaryKey()
                    .references("capture", onDelete: .cascade)
                t.column("visibleTagsJSON", .text).notNull().defaults(to: "[]")
                t.column("hiddenSearchTagsJSON", .text).notNull().defaults(to: "[]")
                t.column("summary", .text)
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("status", .text).notNull()
                t.column("error", .text)
                t.column("confidence", .double)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_captureAIContext_status", on: "captureAIContext", columns: ["status"])
            try db.create(index: "idx_captureAIContext_provider", on: "captureAIContext", columns: ["provider"])
            try db.create(index: "idx_captureTag_captureId", on: "captureTag", columns: ["captureId"])
            try db.create(index: "idx_captureTag_tagId", on: "captureTag", columns: ["tagId"])
        }

        migrator.registerMigration("v4_clear_invalid_ai_tagging_fk_errors") { db in
            try db.execute(sql: """
                DELETE FROM captureAIContext
                WHERE status = ?
                  AND error LIKE ?
                """, arguments: [AITaggingStatus.failed.rawValue, "%FOREIGN KEY constraint failed%"])
        }

        migrator.registerMigration("v5_design_context_diagnostics") { db in
            let existing = try Set(db.columns(in: "capture").map(\.name))
            try db.alter(table: "capture") { t in
                if !existing.contains("designContextStatus") {
                    t.add(column: "designContextStatus", .text)
                }
                if !existing.contains("designContextMessage") {
                    t.add(column: "designContextMessage", .text)
                }
                if !existing.contains("designContextSource") {
                    t.add(column: "designContextSource", .text)
                }
                if !existing.contains("designContextUpdatedAt") {
                    t.add(column: "designContextUpdatedAt", .datetime)
                }
            }
        }

        migrator.registerMigration("v6_tag_symbols") { db in
            let existing = try Set(db.columns(in: "tag").map(\.name))
            if !existing.contains("symbol") {
                try db.alter(table: "tag") { t in
                    t.add(column: "symbol", .text)
                }
            }
        }

        migrator.registerMigration("v7_durable_storage") { db in
            let captureColumns = try Set(db.columns(in: "capture").map(\.name))
            try db.alter(table: "capture") { table in
                if !captureColumns.contains("contentHash") { table.add(column: "contentHash", .text) }
                if !captureColumns.contains("storageStatus") {
                    table.add(column: "storageStatus", .text).defaults(to: "ready")
                }
            }
            try db.create(index: "idx_capture_contentHash", on: "capture", columns: ["contentHash"], unique: true)

            try db.create(table: "captureTag_v7") { table in
                table.column("captureId", .text).notNull().references("capture", onDelete: .cascade)
                table.column("tagId", .text).notNull().references("tag", onDelete: .cascade)
                table.primaryKey(["captureId", "tagId"])
            }
            try db.execute(sql: "INSERT OR IGNORE INTO captureTag_v7 SELECT captureId, tagId FROM captureTag")
            try db.drop(table: "captureTag")
            try db.rename(table: "captureTag_v7", to: "captureTag")
            try db.create(index: "idx_captureTag_captureId_v7", on: "captureTag", columns: ["captureId"])
            try db.create(index: "idx_captureTag_tagId_v7", on: "captureTag", columns: ["tagId"])

            try db.create(table: "fileDeletionQueue") { table in
                table.column("id", .text).primaryKey()
                table.column("path", .text).notNull().unique()
                table.column("createdAt", .datetime).notNull()
                table.column("attemptCount", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
                table.column("nextAttemptAt", .datetime)
            }
            try db.create(index: "idx_fileDeletionQueue_nextAttemptAt", on: "fileDeletionQueue", columns: ["nextAttemptAt"])
        }

        migrator.registerMigration("v8_capture_analysis_search") { db in
            let columns = try Set(db.columns(in: "captureAIContext").map(\.name))
            try db.alter(table: "captureAIContext") { table in
                if !columns.contains("kind") { table.add(column: "kind", .text).notNull().defaults(to: "other") }
                if !columns.contains("suggestedTitle") { table.add(column: "suggestedTitle", .text) }
                if !columns.contains("entitiesJSON") { table.add(column: "entitiesJSON", .text).notNull().defaults(to: "{}") }
                if !columns.contains("ocrText") { table.add(column: "ocrText", .text) }
                if !columns.contains("schemaVersion") { table.add(column: "schemaVersion", .integer).notNull().defaults(to: 2) }
                if !columns.contains("attemptCount") { table.add(column: "attemptCount", .integer).notNull().defaults(to: 0) }
                if !columns.contains("nextRetryAt") { table.add(column: "nextRetryAt", .datetime) }
                if !columns.contains("failureKind") { table.add(column: "failureKind", .text) }
            }
            try db.create(index: "idx_captureAIContext_kind", on: "captureAIContext", columns: ["kind"])
            try db.create(index: "idx_captureAIContext_nextRetryAt", on: "captureAIContext", columns: ["nextRetryAt"])

            try db.execute(sql: """
                CREATE VIRTUAL TABLE captureSearchFTS USING fts5(
                    captureId UNINDEXED,
                    content,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """)
            try db.execute(sql: """
                INSERT INTO captureSearchFTS(captureId, content)
                SELECT id, trim(
                    coalesce(appName, '') || ' ' || coalesce(windowTitle, '') || ' ' ||
                    coalesce(url, '') || ' ' || coalesce(pageTitle, '') || ' ' ||
                    coalesce(songName, '') || ' ' || coalesce(artistName, '') || ' ' ||
                    coalesce(designFileName, '') || ' ' || coalesce(notes, '')
                ) FROM capture
                """)
        }

        migrator.registerMigration("v9_canvas") { db in
            try db.create(table: "canvasPlacement") { table in
                table.column("boardKey", .text).notNull()
                table.column("captureId", .text).notNull().references("capture", onDelete: .cascade)
                table.column("x", .double).notNull()
                table.column("y", .double).notNull()
                table.column("zIndex", .integer).notNull().defaults(to: 0)
                table.column("scale", .double).notNull().defaults(to: 1)
                table.primaryKey(["boardKey", "captureId"])
            }
            try db.create(index: "idx_canvasPlacement_captureId", on: "canvasPlacement", columns: ["captureId"])
        }

        return migrator
    }

    // MARK: - Accessors

    func write<T>(_ updates: @escaping (Database) throws -> T) async throws -> T {
        try setup()
        return try dbQueue!.write(updates)
    }

    func read<T>(_ value: @escaping (Database) throws -> T) async throws -> T {
        try setup()
        return try dbQueue!.read(value)
    }

    func capture(withContentHash hash: String) async throws -> Capture? {
        try await read { db in
            try Capture.filter(Capture.Columns.contentHash == hash).fetchOne(db)
        }
    }

    func deleteCaptureAndEnqueueFiles(id: UUID) async throws {
        try await write { db in
            guard let capture = try Capture.fetchOne(db, key: id) else { return }
            let children = try Capture.filter(Capture.Columns.parentCaptureId == id).fetchAll(db)
            let captures = children + [capture]
            let paths = captures.flatMap { item in
                [item.screenshotPath, item.thumbnailPath, item.faviconPath, item.albumArtPath].compactMap { $0 }
            }
            for path in Set(paths) {
                var record = FileDeletionRecord(
                    id: UUID(), path: path, createdAt: Date(), attemptCount: 0,
                    lastError: nil, nextAttemptAt: nil
                )
                try record.insert(db, onConflict: .ignore)
            }
            for child in children {
                try db.execute(sql: "DELETE FROM captureSearchFTS WHERE captureId = ?", arguments: [child.id])
                _ = try child.delete(db)
            }
            try db.execute(sql: "DELETE FROM captureSearchFTS WHERE captureId = ?", arguments: [capture.id])
            _ = try capture.delete(db)
        }
    }

    func pendingFileDeletions(limit: Int) async throws -> [FileDeletionRecord] {
        try await read { db in
            try FileDeletionRecord.fetchAll(
                db,
                sql: """
                SELECT * FROM fileDeletionQueue
                WHERE nextAttemptAt IS NULL OR nextAttemptAt <= ?
                ORDER BY createdAt ASC LIMIT ?
                """,
                arguments: [Date(), limit]
            )
        }
    }

    func completeFileDeletion(id: UUID) async throws {
        _ = try await write { db in try FileDeletionRecord.deleteOne(db, key: id) }
    }

    func failFileDeletion(id: UUID, error: String) async throws {
        try await write { db in
            guard var record = try FileDeletionRecord.fetchOne(db, key: id) else { return }
            record.attemptCount += 1
            record.lastError = String(error.prefix(500))
            record.nextAttemptAt = Date().addingTimeInterval(min(3600, pow(2, Double(record.attemptCount)) * 5))
            try record.update(db)
        }
    }

    func saveLocalAnalysis(
        captureId: UUID,
        ocrText: String,
        kind: CaptureKind,
        title: String?,
        entitiesJSON: String
    ) async throws {
        try await write { db in
            let existing = try CaptureAIContext.fetchOne(db, key: captureId)
            var context = CaptureAIContext(
                captureId: captureId,
                visibleTags: existing?.visibleTags ?? [],
                hiddenSearchTags: existing?.hiddenSearchTags ?? [],
                summary: existing?.summary,
                provider: existing?.provider ?? "local",
                model: existing?.model ?? "vision-ocr",
                status: existing?.status == .complete ? .complete : .local,
                error: existing?.error,
                confidence: existing?.confidence,
                createdAt: existing?.createdAt ?? Date(),
                updatedAt: Date(),
                kind: kind,
                suggestedTitle: title,
                entitiesJSON: entitiesJSON,
                ocrText: ocrText,
                attemptCount: existing?.attemptCount ?? 0
            )
            try context.save(db)
            try Self.rebuildSearchDocument(captureId: captureId, db: db)
        }
    }

    func canvasPlacements(boardKey: String) async throws -> [CanvasPlacement] {
        try await read { db in
            try CanvasPlacement
                .filter(Column("boardKey") == boardKey)
                .order(Column("zIndex"))
                .fetchAll(db)
        }
    }

    func saveCanvasPlacement(_ placement: CanvasPlacement) async throws {
        try await write { db in
            var mutable = placement
            try mutable.save(db)
        }
    }

    func rebuildSearchDocument(captureId: UUID) async throws {
        try await write { db in try Self.rebuildSearchDocument(captureId: captureId, db: db) }
    }

    private static func rebuildSearchDocument(captureId: UUID, db: Database) throws {
        guard let capture = try Capture.fetchOne(db, key: captureId) else {
            try db.execute(sql: "DELETE FROM captureSearchFTS WHERE captureId = ?", arguments: [captureId])
            return
        }
        let tags = try tagNames(for: captureId, db: db).joined(separator: " ")
        let analysis = try CaptureAIContext.fetchOne(db, key: captureId)
        let collectionName: String = try capture.collectionId.flatMap { id in
            try String.fetchOne(db, sql: "SELECT name FROM collection WHERE id = ?", arguments: [id])
        } ?? ""
        let content = [
            capture.appName, capture.windowTitle, capture.url, capture.pageTitle,
            capture.songName, capture.artistName, capture.albumName, capture.designFileName,
            capture.designPageName, capture.notes, tags, collectionName,
            analysis?.suggestedTitle, analysis?.summary, analysis?.ocrText,
            analysis?.visibleTags.joined(separator: " "),
            analysis?.hiddenSearchTags.joined(separator: " "), analysis?.entitiesJSON
        ].compactMap { $0 }.joined(separator: " ")
        try db.execute(sql: "DELETE FROM captureSearchFTS WHERE captureId = ?", arguments: [captureId])
        try db.execute(
            sql: "INSERT INTO captureSearchFTS(captureId, content) VALUES (?, ?)",
            arguments: [captureId, content]
        )
    }

    // MARK: - Tag helpers

    func ensureTagsExist(_ names: [String]) async throws -> [Tag] {
        try await write { db in
            var tags: [Tag] = []
            for name in names {
                let trimmed = Self.normalizedTagName(name)
                guard !trimmed.isEmpty else { continue }

                if let existing = try Tag.filter(Tag.Columns.name == trimmed).fetchOne(db) {
                    tags.append(existing)
                } else {
                    var tag = Tag(id: UUID(), name: trimmed, usageCount: 0)
                    try tag.insert(db)
                    tags.append(tag)
                }
            }
            return tags
        }
    }

    func linkTags(_ tagIds: [UUID], to captureId: UUID) async throws {
        try await write { db in
            for tagId in tagIds {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO captureTag (captureId, tagId) VALUES (?, ?)",
                    arguments: [captureId, tagId]
                )
            }
            try Self.recalculateTagUsageCounts(db)
            try Self.rebuildSearchDocument(captureId: captureId, db: db)
        }
    }

    func tagNames(for captureId: UUID) async throws -> [String] {
        try await read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT tag.name
                FROM tag
                JOIN captureTag ON captureTag.tagId = tag.id
                WHERE captureTag.captureId = ?
                ORDER BY tag.name COLLATE NOCASE
                """,
                arguments: [captureId]
            )
        }
    }

    func tags(for captureId: UUID) async throws -> [Tag] {
        try await read { db in
            try Tag.fetchAll(
                db,
                sql: """
                SELECT tag.*
                FROM tag
                JOIN captureTag ON captureTag.tagId = tag.id
                WHERE captureTag.captureId = ?
                ORDER BY tag.name COLLATE NOCASE
                """,
                arguments: [captureId]
            )
        }
    }

    func allAITaggingContexts() async throws -> [CaptureAIContext] {
        try await read { db in
            try CaptureAIContext.fetchAll(db)
        }
    }

    func capturesNeedingAITags(limit: Int? = nil) async throws -> [Capture] {
        try await read { db in
            var sql = """
            SELECT capture.*
            FROM capture
            LEFT JOIN captureAIContext ON captureAIContext.captureId = capture.id
            WHERE capture.parentCaptureId IS NULL
              AND (captureAIContext.captureId IS NULL OR captureAIContext.status != ?)
            ORDER BY capture.timestamp DESC
            """
            var arguments: StatementArguments = [AITaggingStatus.complete.rawValue]
            if let limit {
                sql += "\nLIMIT ?"
                arguments += [limit]
            }
            return try Capture.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    func aiTaggingContext(for captureId: UUID) async throws -> CaptureAIContext? {
        try await read { db in
            try CaptureAIContext.fetchOne(db, key: captureId)
        }
    }

    func setTagNames(_ names: [String], for captureId: UUID) async throws {
        try await write { db in
            let normalizedNames = Array(Set(names.map(Self.normalizedTagName).filter { !$0.isEmpty })).sorted()
            try Self.setTagNames(normalizedNames, for: captureId, db: db)
            try Self.recalculateTagUsageCounts(db)
            try Self.deleteUnusedTags(db)
            try Self.rebuildSearchDocument(captureId: captureId, db: db)
        }
    }

    func addTagNames(_ names: [String], to captureIds: Set<UUID>) async throws {
        guard !captureIds.isEmpty else { return }
        try await write { db in
            let normalizedNames = Array(Set(names.map(Self.normalizedTagName).filter { !$0.isEmpty })).sorted()
            guard !normalizedNames.isEmpty else { return }
            for captureId in captureIds {
                var existingNames = try Self.tagNames(for: captureId, db: db)
                existingNames.formUnion(normalizedNames)
                try Self.setTagNames(Array(existingNames).sorted(), for: captureId, db: db)
                try Self.rebuildSearchDocument(captureId: captureId, db: db)
            }
            try Self.recalculateTagUsageCounts(db)
            try Self.deleteUnusedTags(db)
        }
    }

    func removeTagNames(_ names: [String], from captureIds: Set<UUID>) async throws {
        guard !captureIds.isEmpty else { return }
        try await write { db in
            let normalizedNames = Set(names.map(Self.normalizedTagName).filter { !$0.isEmpty })
            guard !normalizedNames.isEmpty else { return }
            for captureId in captureIds {
                var existingNames = try Self.tagNames(for: captureId, db: db)
                existingNames.subtract(normalizedNames)
                try Self.setTagNames(Array(existingNames).sorted(), for: captureId, db: db)
                try Self.rebuildSearchDocument(captureId: captureId, db: db)
            }
            try Self.recalculateTagUsageCounts(db)
            try Self.deleteUnusedTags(db)
        }
    }

    func saveAITaggingContext(_ context: CaptureAIContext) async throws {
        try await write { db in
            var mutable = context
            try mutable.save(db)
            try Self.rebuildSearchDocument(captureId: context.captureId, db: db)
        }
    }

    func renameTag(id: UUID, to newName: String) async throws {
        try await write { db in
            let normalized = Self.normalizedTagName(newName)
            guard !normalized.isEmpty,
                  let tag = try Tag.fetchOne(db, key: id) else { return }

            if let existing = try Tag.filter(Tag.Columns.name == normalized).fetchOne(db),
               existing.id != id {
                try Self.mergeTag(db, sourceId: tag.id, destinationId: existing.id)
            } else {
                var updated = tag
                updated.name = normalized
                try updated.update(db)
            }
            try Self.recalculateTagUsageCounts(db)
            try Self.deleteUnusedTags(db)
        }
    }

    func updateTagSymbol(id: UUID, symbol: String?) async throws {
        try await write { db in
            guard var tag = try Tag.fetchOne(db, key: id) else { return }
            tag.symbol = TagSymbol.normalizedStorageValue(symbol)
            try tag.update(db)
        }
    }

    func updateCollection(id: UUID, name: String, symbol: String?) async throws {
        try await write { db in
            guard var collection = try Collection.fetchOne(db, key: id) else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            collection.name = trimmed
            collection.icon = TagSymbol.normalizedStorageValue(symbol) ?? "emoji:📁"
            try collection.update(db)
        }
    }

    func deleteTag(id: UUID) async throws {
        try await write { db in
            try CaptureTag
                .filter(Column("tagId") == id)
                .deleteAll(db)
            try Tag.deleteOne(db, key: id)
            try Self.recalculateTagUsageCounts(db)
        }
    }

    func mergeTag(sourceId: UUID, into destinationId: UUID) async throws {
        try await write { db in
            try Self.mergeTag(db, sourceId: sourceId, destinationId: destinationId)
            try Self.recalculateTagUsageCounts(db)
            try Self.deleteUnusedTags(db)
        }
    }

    nonisolated private static func normalizedTagName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func normalizedTagNames(_ values: [String]) -> [String] {
        Array(Set(values.map(normalizedTagName).filter { !$0.isEmpty })).sorted()
    }

    private static func tagNames(for captureId: UUID, db: Database) throws -> Set<String> {
        let names = try String.fetchAll(
            db,
            sql: """
            SELECT tag.name
            FROM tag
            JOIN captureTag ON captureTag.tagId = tag.id
            WHERE captureTag.captureId = ?
            """,
            arguments: [captureId]
        )
        return Set(names)
    }

    private static func setTagNames(_ names: [String], for captureId: UUID, db: Database) throws {
        guard try Capture.fetchOne(db, key: captureId) != nil else {
            throw TaggingDatabaseError.captureMissing
        }

        try CaptureTag
            .filter(Column("captureId") == captureId)
            .deleteAll(db)

        for name in names {
            let tag: Tag
            if let existing = try Tag.filter(Tag.Columns.name == name).fetchOne(db) {
                tag = existing
            } else {
                var created = Tag(id: UUID(), name: name, usageCount: 0)
                try created.insert(db)
                tag = created
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO captureTag (captureId, tagId) VALUES (?, ?)",
                arguments: [captureId, tag.id]
            )
        }
    }

    private static func mergeTag(_ db: Database, sourceId: UUID, destinationId: UUID) throws {
        guard sourceId != destinationId else { return }
        let captureIds = try UUID.fetchAll(
            db,
            sql: "SELECT captureId FROM captureTag WHERE tagId = ?",
            arguments: [sourceId]
        )
        for captureId in captureIds {
            try db.execute(
                sql: "INSERT OR IGNORE INTO captureTag (captureId, tagId) VALUES (?, ?)",
                arguments: [captureId, destinationId]
            )
        }
        try CaptureTag
            .filter(Column("tagId") == sourceId)
            .deleteAll(db)
        try Tag.deleteOne(db, key: sourceId)
    }

    private static func recalculateTagUsageCounts(_ db: Database) throws {
        try db.execute(sql: """
            UPDATE tag
            SET usageCount = (
                SELECT COUNT(*)
                FROM captureTag
                WHERE captureTag.tagId = tag.id
            )
            """)
    }

    private static func deleteUnusedTags(_ db: Database) throws {
        try Tag.filter(Column("usageCount") == 0).deleteAll(db)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let newCaptureCreated = Notification.Name("EZClipNewCaptureCreated")
    static let captureDeleted = Notification.Name("EZClipCaptureDeleted")
    static let captureTagsChanged = Notification.Name("EZClipCaptureTagsChanged")
    static let captureAIContextChanged = Notification.Name("EZClipCaptureAIContextChanged")
}
