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
    @Published var isSelectionMode = false
    @Published var selectedCaptureIDs: Set<UUID> = []

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

    var selectedCollection: Collection? {
        guard let selectedCollectionId else { return nil }
        return collections.first { $0.id == selectedCollectionId }
    }

    func showAllCaptures() {
        selectedContextType = nil
        selectedCollectionId = nil
        selectedTagName = nil
        clearSelection()
    }

    func selectContextType(_ type: ContextType) {
        selectedCollectionId = nil
        selectedTagName = nil
        selectedContextType = selectedContextType == type ? nil : type
        clearSelection()
    }

    func selectCollection(_ collectionId: UUID?) {
        selectedContextType = nil
        selectedTagName = nil
        selectedCollectionId = collectionId
        clearSelection()
    }

    func selectTag(_ tagName: String) {
        selectedContextType = nil
        selectedCollectionId = nil
        selectedTagName = selectedTagName == tagName ? nil : tagName
        clearSelection()
    }

    func deleteCapture(_ capture: Capture) async {
        do {
            captures.removeAll { $0.id == capture.id || $0.parentCaptureId == capture.id }
            selectedCaptureIDs.remove(capture.id)
            try await CaptureOrchestrator.shared.delete(capture)
            await loadAll()
        } catch {
            print("Failed to delete: \(error)")
            await loadAll()
        }
    }

    func deleteSelectedCaptures() async {
        let selected = captures.filter { selectedCaptureIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        captures.removeAll { selectedCaptureIDs.contains($0.id) }
        selectedCaptureIDs.removeAll()
        isSelectionMode = false

        for capture in selected {
            do {
                try await CaptureOrchestrator.shared.delete(capture)
            } catch {
                print("Failed to delete selected capture: \(error)")
            }
        }
        await loadAll()
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
            if let index = captures.firstIndex(where: { $0.id == captureId }) {
                captures[index].collectionId = collectionId
            }
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

    func assignSelectedCaptures(to collectionId: UUID?) async {
        let ids = selectedCaptureIDs
        guard !ids.isEmpty else { return }

        for index in captures.indices where ids.contains(captures[index].id) {
            captures[index].collectionId = collectionId
        }
        selectedCaptureIDs.removeAll()
        isSelectionMode = false

        do {
            try await db.write { db in
                for id in ids {
                    if var capture = try Capture.fetchOne(db, key: id) {
                        capture.collectionId = collectionId
                        try capture.update(db)
                    }
                }
            }
            await loadAll()
        } catch {
            print("Failed to assign selected captures: \(error)")
            await loadAll()
        }
    }

    func toggleSelection(for capture: Capture) {
        if selectedCaptureIDs.contains(capture.id) {
            selectedCaptureIDs.remove(capture.id)
        } else {
            selectedCaptureIDs.insert(capture.id)
        }
    }

    func clearSelection() {
        selectedCaptureIDs.removeAll()
        isSelectionMode = false
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
