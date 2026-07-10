import SwiftUI
import Combine
import GRDB
import AppKit
import Observation

@Observable
@MainActor
final class LibraryViewModel {
    var captures: [Capture] = []
    var collections: [Collection] = []
    var tags: [Tag] = []
    var captureTagsByCaptureID: [UUID: Set<String>] = [:]
    var aiContextsByCaptureID: [UUID: CaptureAIContext] = [:]
    var searchText: String = ""
    var selectedContextType: ContextType?
    var selectedCaptureKind: CaptureKind?
    var selectedCollectionId: UUID?
    var selectedTagName: String?
    var selectedCapture: Capture?
    var sortOrder: SortOrder = .newest
    var isLoading = false
    var isLoadingNextPage = false
    var hasMoreCaptures = false
    var isSelectionMode = false
    var selectedCaptureIDs: Set<UUID> = []
    var lastSelectedCaptureID: UUID?

    private let db = DatabaseManager.shared
    private let pageSize = 200

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
            let snapshot = try await fetchSnapshot(after: nil)
            captures = snapshot.captures
            collections = snapshot.collections
            tags = snapshot.tags
            captureTagsByCaptureID = snapshot.captureTags
            aiContextsByCaptureID = snapshot.analyses
            hasMoreCaptures = snapshot.captures.count == pageSize
        } catch {
            print("Failed to load library: \(error)")
        }
    }

    func loadNextPage() async {
        guard hasMoreCaptures, !isLoadingNextPage, let cursor = captures.last else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }
        do {
            let snapshot = try await fetchSnapshot(after: cursor)
            let existing = Set(captures.map(\.id))
            captures.append(contentsOf: snapshot.captures.filter { !existing.contains($0.id) })
            captureTagsByCaptureID.merge(snapshot.captureTags) { _, new in new }
            aiContextsByCaptureID.merge(snapshot.analyses) { _, new in new }
            hasMoreCaptures = snapshot.captures.count == pageSize
        } catch {
            print("Failed to load next library page: \(error)")
        }
    }

    var filteredCaptures: [Capture] {
        var results = captures

        if let type = selectedContextType {
            results = results.filter { $0.contextType == type }
        }

        if let selectedCaptureKind {
            results = results.filter { aiContextsByCaptureID[$0.id]?.kind == selectedCaptureKind }
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

    var visibleSidebarTags: [Tag] {
        tags.filter { !TagVisibility.isHiddenInSidebar($0.name, captures: captures) }
    }

    var selectedCollection: Collection? {
        guard let selectedCollectionId else { return nil }
        return collections.first { $0.id == selectedCollectionId }
    }

    func showAllCaptures() {
        selectedContextType = nil
        selectedCaptureKind = nil
        selectedCollectionId = nil
        selectedTagName = nil
        clearSelection()
    }

    func selectContextType(_ type: ContextType) {
        selectedCaptureKind = nil
        selectedCollectionId = nil
        selectedTagName = nil
        selectedContextType = selectedContextType == type ? nil : type
        clearSelection()
        Task { await loadAll() }
    }

    func selectCaptureKind(_ kind: CaptureKind) {
        selectedContextType = nil
        selectedCollectionId = nil
        selectedTagName = nil
        selectedCaptureKind = selectedCaptureKind == kind ? nil : kind
        clearSelection()
        Task { await loadAll() }
    }

    func selectCollection(_ collectionId: UUID?) {
        selectedContextType = nil
        selectedCaptureKind = nil
        selectedTagName = nil
        selectedCollectionId = collectionId
        clearSelection()
        Task { await loadAll() }
    }

    func selectTag(_ tagName: String) {
        selectedContextType = nil
        selectedCaptureKind = nil
        selectedCollectionId = nil
        selectedTagName = selectedTagName == tagName ? nil : tagName
        clearSelection()
        Task { await loadAll() }
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
            try await db.rebuildSearchDocument(captureId: updated.id)
            await loadAll()
        } catch {
            print("Failed to update notes: \(error)")
        }
    }

    @discardableResult
    func addCollection(name: String, color: String = "blue", icon: String = "emoji:📁") async -> Collection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var collection = Collection(
            id: UUID(),
            name: trimmed,
            color: color,
            icon: TagSymbol.normalizedStorageValue(icon) ?? "emoji:📁",
            sortOrder: collections.count
        )
        do {
            try await db.write { db in
                try collection.insert(db)
            }
            await loadAll()
            return collection
        } catch {
            print("Failed to create collection: \(error)")
            return nil
        }
    }

    func addCollectionAndAssignSelectedCaptures(name: String) async {
        guard !selectedCaptureIDs.isEmpty else { return }
        guard let collection = await addCollection(name: name) else { return }
        await assignSelectedCaptures(to: collection.id)
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
            try await db.rebuildSearchDocument(captureId: captureId)
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
            for id in ids { try await db.rebuildSearchDocument(captureId: id) }
            await loadAll()
        } catch {
            print("Failed to assign selected captures: \(error)")
            await loadAll()
        }
    }

    func updateCollection(_ collection: Collection, name: String, symbol: String?) async {
        do {
            try await db.updateCollection(id: collection.id, name: name, symbol: symbol)
            await loadAll()
        } catch {
            print("Failed to update collection: \(error)")
        }
    }

    func updateTagSymbol(_ tag: Tag, symbol: String?) async {
        do {
            try await db.updateTagSymbol(id: tag.id, symbol: symbol)
            await loadAll()
            NotificationCenter.default.post(name: .captureTagsChanged, object: nil)
        } catch {
            print("Failed to update tag symbol: \(error)")
        }
    }

    func visibleTags(for capture: Capture) -> [Tag] {
        tagRecords(for: capture).filter { !TagVisibility.isHidden($0.name, for: capture) }
    }

    func hiddenTags(for capture: Capture) -> [Tag] {
        tagRecords(for: capture).filter { TagVisibility.isHidden($0.name, for: capture) }
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

    private func tagRecords(for capture: Capture) -> [Tag] {
        let names = captureTagsByCaptureID[capture.id] ?? []
        return tags
            .filter { names.contains($0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    private struct Snapshot {
        var captures: [Capture]
        var collections: [Collection]
        var tags: [Tag]
        var captureTags: [UUID: Set<String>]
        var analyses: [UUID: CaptureAIContext]
    }

    private func fetchSnapshot(after cursor: Capture?) async throws -> Snapshot {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedContextType = selectedContextType
        let selectedCaptureKind = selectedCaptureKind
        let selectedCollectionId = selectedCollectionId
        let selectedTagName = selectedTagName
        let sortOrder = sortOrder
        let pageSize = pageSize

        return try await db.read { database in
            var joins: [String] = []
            var predicates = ["capture.parentCaptureId IS NULL"]
            var arguments = StatementArguments()

            if !query.isEmpty {
                joins.append("JOIN captureSearchFTS ON captureSearchFTS.captureId = capture.id")
                predicates.append("captureSearchFTS MATCH ?")
                arguments += [Self.ftsQuery(query)]
            }
            if let selectedCaptureKind {
                joins.append("JOIN captureAIContext analysis ON analysis.captureId = capture.id")
                predicates.append("analysis.kind = ?")
                arguments += [selectedCaptureKind.rawValue]
            }
            if let selectedContextType {
                predicates.append("capture.contextType = ?")
                arguments += [selectedContextType.rawValue]
            }
            if let selectedCollectionId {
                predicates.append("capture.collectionId = ?")
                arguments += [selectedCollectionId]
            }
            if let selectedTagName {
                predicates.append("EXISTS (SELECT 1 FROM captureTag ct JOIN tag t ON t.id = ct.tagId WHERE ct.captureId = capture.id AND t.name = ?)")
                arguments += [selectedTagName]
            }
            if let cursor {
                predicates.append(sortOrder.cursorPredicate)
                arguments += sortOrder.cursorArguments(cursor)
            }
            arguments += [pageSize]
            let sql = """
                SELECT capture.* FROM capture
                \(joins.joined(separator: " "))
                WHERE \(predicates.joined(separator: " AND "))
                ORDER BY \(sortOrder.orderSQL), capture.id \(sortOrder.idDirection)
                LIMIT ?
                """
            let captures = try Capture.fetchAll(database, sql: sql, arguments: arguments)
            let ids = captures.map(\.id)
            let collections = cursor == nil ? try Collection.order(Collection.Columns.sortOrder).fetchAll(database) : []
            let tags = cursor == nil ? try Tag.order(Tag.Columns.usageCount.desc).fetchAll(database) : []
            guard !ids.isEmpty else {
                return Snapshot(captures: [], collections: collections, tags: tags, captureTags: [:], analyses: [:])
            }
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let tagRows = try Row.fetchAll(
                database,
                sql: "SELECT captureTag.captureId, tag.name FROM captureTag JOIN tag ON tag.id = captureTag.tagId WHERE captureTag.captureId IN (\(placeholders))",
                arguments: StatementArguments(ids)
            )
            var tagsByCapture: [UUID: Set<String>] = [:]
            for row in tagRows {
                if let id: UUID = row["captureId"], let name: String = row["name"] {
                    tagsByCapture[id, default: []].insert(name)
                }
            }
            let analyses = try CaptureAIContext
                .filter(ids.contains(CaptureAIContext.Columns.captureId))
                .fetchAll(database)
                .reduce(into: [UUID: CaptureAIContext]()) { $0[$1.captureId] = $1 }
            return Snapshot(captures: captures, collections: collections, tags: tags, captureTags: tagsByCapture, analyses: analyses)
        }
    }

    nonisolated private static func ftsQuery(_ value: String) -> String {
        value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
            .joined(separator: " AND ")
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

    var idDirection: String { self == .newest ? "DESC" : "ASC" }

    var cursorPredicate: String {
        switch self {
        case .newest: "(capture.timestamp < ? OR (capture.timestamp = ? AND capture.id < ?))"
        case .oldest: "(capture.timestamp > ? OR (capture.timestamp = ? AND capture.id > ?))"
        case .appName: "(capture.appName COLLATE NOCASE > ? OR (capture.appName = ? AND capture.id > ?))"
        }
    }

    func cursorArguments(_ capture: Capture) -> StatementArguments {
        switch self {
        case .newest, .oldest: [capture.timestamp, capture.timestamp, capture.id]
        case .appName: [capture.appName, capture.appName, capture.id]
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
