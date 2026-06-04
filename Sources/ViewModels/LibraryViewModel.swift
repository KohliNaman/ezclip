import SwiftUI
import Combine
import GRDB

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var captures: [Capture] = []
    @Published var collections: [Collection] = []
    @Published var tags: [Tag] = []
    @Published var searchText: String = ""
    @Published var selectedContextType: ContextType?
    @Published var selectedCollectionId: UUID?
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
                    .order(sql: sortOrder.orderSQL)
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

        switch sortOrder {
        case .newest:
            results.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            results.sort { $0.timestamp < $1.timestamp }
        case .appName:
            results.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        }

        return results
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
