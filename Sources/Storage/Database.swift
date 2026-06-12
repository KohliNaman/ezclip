import Foundation
import GRDB

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

    // MARK: - Tag helpers

    func ensureTagsExist(_ names: [String]) async throws -> [Tag] {
        try await write { db in
            var tags: [Tag] = []
            for name in names {
                let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
                guard !trimmed.isEmpty else { continue }

                if var existing = try Tag.filter(Tag.Columns.name == trimmed).fetchOne(db) {
                    existing.usageCount += 1
                    try existing.update(db)
                    tags.append(existing)
                } else {
                    var tag = Tag(id: UUID(), name: trimmed, usageCount: 1)
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
                var ct = CaptureTag(captureId: captureId, tagId: tagId)
                try ct.insert(db)
            }
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let newCaptureCreated = Notification.Name("EZClipNewCaptureCreated")
    static let captureDeleted = Notification.Name("EZClipCaptureDeleted")
}
