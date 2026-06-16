import SwiftUI
import Combine
import GRDB
import AppKit

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var captures: [Capture] = []
    @Published var collections: [Collection] = []
    @Published var tags: [Tag] = []
    @Published var captureTagsByCaptureID: [UUID: Set<String>] = [:]
    @Published var aiContextsByCaptureID: [UUID: CaptureAIContext] = [:]
    @Published var searchText: String = ""
    @Published var selectedContextType: ContextType?
    @Published var selectedCollectionId: UUID?
    @Published var selectedTagName: String?
    @Published var selectedCapture: Capture?
    @Published var sortOrder: SortOrder = .newest
    @Published var isLoading = false
    @Published var isSelectionMode = false
    @Published var selectedCaptureIDs: Set<UUID> = []
    @Published var lastSelectedCaptureID: UUID?

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
            aiContextsByCaptureID = try await self.db.allAITaggingContexts()
                .reduce(into: [:]) { partial, context in
                    partial[context.captureId] = context
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

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            results = results.filter { capture in
                capture.appName.localizedCaseInsensitiveContains(query) ||
                capture.windowTitle.localizedCaseInsensitiveContains(query) ||
                (capture.url?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.pageTitle?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.songName?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.artistName?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.designFileName?.localizedCaseInsensitiveContains(query) ?? false) ||
                (capture.notes?.localizedCaseInsensitiveContains(query) ?? false) ||
                tagContextMatches(capture, query: query) ||
                aiContextMatches(capture, query: query) ||
                designContextMatches(capture.designContextJSON, query: query)
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

    func renameTag(_ tag: Tag, to name: String) async {
        do {
            try await db.renameTag(id: tag.id, to: name)
            if selectedTagName == tag.name {
                selectedTagName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            await loadAll()
        } catch {
            print("Failed to rename tag: \(error)")
        }
    }

    func deleteTag(_ tag: Tag) async {
        do {
            try await db.deleteTag(id: tag.id)
            if selectedTagName == tag.name { selectedTagName = nil }
            await loadAll()
        } catch {
            print("Failed to delete tag: \(error)")
        }
    }

    func mergeTag(_ source: Tag, into destination: Tag) async {
        do {
            try await db.mergeTag(sourceId: source.id, into: destination.id)
            if selectedTagName == source.name { selectedTagName = destination.name }
            await loadAll()
        } catch {
            print("Failed to merge tag: \(error)")
        }
    }

    func addTags(_ tagInput: String, to captureIds: Set<UUID>) async {
        let names = Self.parseTagInput(tagInput)
        guard !names.isEmpty, !captureIds.isEmpty else { return }
        do {
            try await db.addTagNames(names, to: captureIds)
            selectedCaptureIDs.removeAll()
            lastSelectedCaptureID = nil
            isSelectionMode = false
            await loadAll()
            NotificationCenter.default.post(name: .captureTagsChanged, object: nil)
        } catch {
            print("Failed to add tags: \(error)")
        }
    }

    func removeTags(_ tagInput: String, from captureIds: Set<UUID>) async {
        let names = Self.parseTagInput(tagInput)
        guard !names.isEmpty, !captureIds.isEmpty else { return }
        do {
            try await db.removeTagNames(names, from: captureIds)
            selectedCaptureIDs.removeAll()
            lastSelectedCaptureID = nil
            isSelectionMode = false
            await loadAll()
            NotificationCenter.default.post(name: .captureTagsChanged, object: nil)
        } catch {
            print("Failed to remove tags: \(error)")
        }
    }

    func generateAITags(for capture: Capture) async {
        await AITaggingService.shared.generateTags(for: capture)
        await loadAll()
    }

    func generateAITagsForSelectedCaptures() async {
        let selected = captures.filter { selectedCaptureIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        await AITaggingService.shared.generateTags(for: selected)
        selectedCaptureIDs.removeAll()
        lastSelectedCaptureID = nil
        isSelectionMode = false
        await loadAll()
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
        lastSelectedCaptureID = nil
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
        lastSelectedCaptureID = nil
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

    func toggleSelection(for capture: Capture, in visibleCaptures: [Capture]? = nil, extendRange: Bool = false) {
        if extendRange,
           let visibleCaptures,
           let lastSelectedCaptureID,
           let anchor = visibleCaptures.firstIndex(where: { $0.id == lastSelectedCaptureID }),
           let target = visibleCaptures.firstIndex(where: { $0.id == capture.id }) {
            let range = min(anchor, target)...max(anchor, target)
            for index in range {
                selectedCaptureIDs.insert(visibleCaptures[index].id)
            }
            return
        }

        if selectedCaptureIDs.contains(capture.id) {
            selectedCaptureIDs.remove(capture.id)
        } else {
            selectedCaptureIDs.insert(capture.id)
        }
        lastSelectedCaptureID = capture.id
    }

    func clearSelection() {
        selectedCaptureIDs.removeAll()
        lastSelectedCaptureID = nil
        isSelectionMode = false
    }

    func copySelectedImagesToClipboard() {
        let images = captures
            .filter { selectedCaptureIDs.contains($0.id) }
            .compactMap { ImageStorageManager.shared.fullImage(for: $0) }
        guard !images.isEmpty else { return }
        ClipboardManager.shared.copyToClipboard(images)
    }

    private func tagContextMatches(_ capture: Capture, query: String) -> Bool {
        captureTagsByCaptureID[capture.id]?.contains { tag in
            tag.localizedCaseInsensitiveContains(query)
        } == true
    }

    private func aiContextMatches(_ capture: Capture, query: String) -> Bool {
        guard let context = aiContextsByCaptureID[capture.id] else { return false }
        return context.visibleTags.contains { $0.localizedCaseInsensitiveContains(query) } ||
        context.hiddenSearchTags.contains { $0.localizedCaseInsensitiveContains(query) } ||
        (context.summary?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func designContextMatches(_ json: String?, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if json?.localizedCaseInsensitiveContains(query) == true {
            return true
        }
        guard let context = BrowserDesignContextStore.decode(json) else { return false }
        return context.fonts.contains { font in
            font.fontFamily.localizedCaseInsensitiveContains(query) ||
            font.fontSize.localizedCaseInsensitiveContains(query) ||
            font.fontWeight.localizedCaseInsensitiveContains(query) ||
            font.sampleText.localizedCaseInsensitiveContains(query)
        } ||
        context.colors.contains { color in
            color.role.localizedCaseInsensitiveContains(query) ||
            color.value.localizedCaseInsensitiveContains(query) ||
            color.value.cssHexOrOriginalForSearch.localizedCaseInsensitiveContains(query)
        } ||
        context.cssTokens.contains { token in
            token.name.localizedCaseInsensitiveContains(query) ||
            token.value.localizedCaseInsensitiveContains(query)
        } ||
        context.buttons.contains { button in
            button.text.localizedCaseInsensitiveContains(query) ||
            (button.backgroundColor?.localizedCaseInsensitiveContains(query) ?? false) ||
            (button.color?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    static func parseTagInput(_ input: String) -> [String] {
        DatabaseManager.normalizedTagNames(
            input
                .split { character in
                    character == "," || character == "\n"
                }
                .map(String.init)
        )
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

private extension String {
    var cssHexOrOriginalForSearch: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let range = trimmed.range(of: #"rgba?\(([^\)]+)\)"#, options: .regularExpression) else {
            return self
        }
        let body = trimmed[range].drop { $0 != "(" }.dropFirst().dropLast()
        let parts = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return self }
        return "#" + parts.prefix(3)
            .map { String(format: "%02x", Int(max(0, min(255, $0)))) }
            .joined()
    }
}
