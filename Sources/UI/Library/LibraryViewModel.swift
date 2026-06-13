import SwiftUI
import Combine
import GRDB

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var captures: [Capture] = []
    @Published var collections: [Collection] = []
    @Published var tags: [Tag] = []
    @Published var captureTagsByCaptureID: [UUID: Set<String>] = [:]
    @Published var searchText: String = ""
    @Published var selectedContextType: ContextType?
    @Published var selectedCollectionId: UUID?
    @Published var selectedTagName: String?
    @Published var selectedCapture: Capture?
    @Published var sortOrder: SortOrder = .newest
    @Published var isLoading = false

    private let db = DatabaseManager.shared

    enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        case appName = "App Name"

        var id: String { rawValue }
    }

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }

        do {
            captures = try await db.read { db in
                try Capture
                    .filter(sql: "parentCaptureId IS NULL")
                    .order(sql: self.sortOrder.orderSQL)
                    .fetchAll(db)
            }
            collections = try await db.read { db in
                try Collection
                    .order(Collection.Columns.sortOrder)
                    .fetchAll(db)
            }
            tags = try await db.read { db in
                try Tag
                    .order(Tag.Columns.usageCount.desc)
                    .fetchAll(db)
            }
            captureTagsByCaptureID = try await db.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT captureTag.captureId, tag.name
                    FROM captureTag
                    JOIN tag ON tag.id = captureTag.tagId
                    """
                )

                var tagsByCapture: [UUID: Set<String>] = [:]
                for row in rows {
                    guard
                        let captureId: UUID = row["captureId"],
                        let tagName: String = row["name"]
                    else { continue }
                    tagsByCapture[captureId, default: []].insert(tagName)
                }
                return tagsByCapture
            }
        } catch {
            print("Failed to load library: \(error)")
        }
    }

    var filteredCaptures: [Capture] {
        var results = captures

        if let type = selectedContextType {
            results = results.filter { $0.contextType == type }
        }

        if let collectionId = selectedCollectionId {
            results = results.filter { $0.collectionId == collectionId }
        }

        if let selectedTagName {
            results = results.filter { capture in
                captureTagsByCaptureID[capture.id]?.contains(selectedTagName) == true
            }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { capture in
                capture.appName.localizedCaseInsensitiveContains(query) ||
                capture.windowTitle.localizedCaseInsensitiveContains(query) ||
                (capture.url?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.pageTitle?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.songName?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.artistName?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.designFileName?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        switch self.sortOrder {
        case .newest:
            results.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            results.sort { $0.timestamp < $1.timestamp }
        case .appName:
            results.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        }

        return results
    }

    var totalCapturesCount: Int { captures.count }

    func showAllCaptures() {
        selectedContextType = nil
        selectedCollectionId = nil
        selectedTagName = nil
    }

    func selectContextType(_ type: ContextType) {
        selectedCollectionId = nil
        selectedTagName = nil
        selectedContextType = selectedContextType == type ? nil : type
    }

    func selectCollection(_ collectionId: UUID?) {
        selectedContextType = nil
        selectedTagName = nil
        selectedCollectionId = collectionId
    }

    func selectTag(_ tagName: String) {
        selectedContextType = nil
        selectedCollectionId = nil
        selectedTagName = selectedTagName == tagName ? nil : tagName
    }

    func deleteCapture(_ capture: Capture) async {
        do {
            try await CaptureOrchestrator.shared.delete(capture)
            await loadAll()
        } catch {
            print("Failed to delete: \(error)")
        }
    }

    func updateNotes(_ notes: String, for capture: Capture) async {
        var updated = capture
        updated.notes = notes.isEmpty ? nil : notes
        do {
            try await db.write { db in
                try updated.update(db)
            }
            await loadAll()
        } catch {
            print("Failed to update notes: \(error)")
        }
    }

    func addCollection(name: String, color: String = "blue", icon: String = "folder") async {
        var collection = Collection(
            id: UUID(),
            name: name,
            color: color,
            icon: icon,
            sortOrder: collections.count
        )
        do {
            try await db.write { db in
                try collection.insert(db)
            }
            await loadAll()
        } catch {
            print("Failed to create collection: \(error)")
        }
    }

    func assignToCollection(_ captureId: UUID, collectionId: UUID?) async {
        do {
            try await db.write { db in
                if var capture = try Capture.fetchOne(db, key: captureId) {
                    capture.collectionId = collectionId
                    try capture.update(db)
                }
            }
            await loadAll()
        } catch {
            print("Failed to assign collection: \(error)")
        }
    }
}

// MARK: - Sort order SQL

private extension LibraryViewModel.SortOrder {
    var orderSQL: String {
        switch self {
        case .newest: "timestamp DESC"
        case .oldest: "timestamp ASC"
        case .appName: "appName ASC"
        }
    }
}
