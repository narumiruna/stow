import Foundation
import StowCore
import SwiftData

private struct SearchWindow: Equatable {
    var after: BridgeTimestamp?
    var before: BridgeTimestamp?
    func contains(_ date: Date) -> Bool {
        let value = BridgeTimestamp(date)
        return (after == nil || value >= after!) && (before == nil || value <= before!)
    }
}

@MainActor
final class StoreOwner {
    private var rootStorage: PreviewRoot?
    private var containerStorage: ModelContainer?
    private var repositoryStorage: StowRepository?
    var root: PreviewRoot { rootStorage! }
    var container: ModelContainer { containerStorage! }
    var repository: StowRepository { repositoryStorage! }
    private var index: SQLiteSearchIndex?
    private var pinnedIndex: SQLiteSearchIndex?
    private var dirty = true
    private var indexedWindow = SearchWindow()
    // Internal dependency injection is not reachable through the production ABI.
    var makeIndex: (URL) throws -> SQLiteSearchIndex = { try SQLiteSearchIndex(url: $0) }

    init(path: String) throws {
        let root = try PreviewRoot(path: path)
        let container = try StowContainerFactory.local(url: root.url.appendingPathComponent(PreviewRoot.storeName))
        self.rootStorage = root
        self.containerStorage = container
        self.repositoryStorage = StowRepository(modelContext: container.mainContext)
    }

    isolated deinit { close() }

    func close() {
        index = nil
        pinnedIndex = nil
        repositoryStorage = nil
        containerStorage = nil
        // Release the exclusive writer lock only after its storage resources.
        rootStorage = nil
    }

    func execute(_ request: BridgeRequest) async throws -> BridgeJSON {
        do {
            if request.command != "close" { try ensureStorage() }
            switch request.command {
            case "get":
                struct Get: Decodable { let id: UUID }
                let r = try request.payload.decode(Get.self)
                return try detail(required(r.id))
            case "create": return try create(request.payload.decode(BridgeCreateRequest.self))
            case "update": return try update(request.payload.decode(BridgeUpdateRequest.self))
            case "apply": return try apply(request.payload.decode(BridgeApplyRequest.self))
            case "search": return try await search(request.payload.decode(BridgeSearchRequest.self))
            case "rebuild": try await rebuild(); return .null
            case "close": return .null
            default: throw BridgeFailure.invalid
            }
        } catch let error as BridgeFailure { throw error }
        catch is DecodingError { throw BridgeFailure.invalid }
        catch is CaptureValidationError { throw BridgeFailure.invalid }
        catch {
            containerStorage?.mainContext.rollback()
            // A failed native save can leave changed registered objects after rollback.
            // Keep the writer lock, but do not reuse that container or context.
            discardFailedStorage()
            throw BridgeFailure.storage
        }
    }

    func discardFailedStorage() {
        index = nil
        pinnedIndex = nil
        repositoryStorage = nil
        containerStorage = nil
        dirty = true
    }

    private func ensureStorage() throws {
        guard containerStorage == nil else { return }
        // Recovery must not silently create an empty replacement for a missing store.
        try root.requireExistingStore()
        let container = try StowContainerFactory.local(url: root.url.appendingPathComponent(PreviewRoot.storeName))
        containerStorage = container
        repositoryStorage = StowRepository(modelContext: container.mainContext)
    }

    private func required(_ id: UUID) throws -> StowItem {
        guard let item = try repository.item(id: id) else { throw BridgeFailure.missing }
        return item
    }

    private func create(_ r: BridgeCreateRequest) throws -> BridgeJSON {
        guard r.item_type == .text || r.item_type == .code || r.item_type == .link else {
            throw BridgeFailure.unsupported
        }
        if r.item_type == .link { try Self.validateURL(r.url_string) }
        let draft = try CaptureDraft(
            id: r.capture_id, type: r.item_type, title: r.title,
            textContent: r.text_content, urlString: r.url_string,
            sourceApp: r.source_app, note: r.note, language: r.language,
            isPinned: r.is_pinned ?? false, directlyArchive: r.directly_archive ?? false
        ).normalized()
        let replayed = try repository.allItems().contains { $0.captureID == r.capture_id }
        let item = try repository.create(from: draft)
        if !replayed { dirty = true }
        return try detail(item, replayed: replayed)
    }

    private func update(_ r: BridgeUpdateRequest) throws -> BridgeJSON {
        try BridgeDate.validateRevision(r.expected_updated_at)
        let item = try required(r.id)
        guard BridgeDate.string(item.updatedAt) == r.expected_updated_at else { throw BridgeFailure.conflict }
        try repository.update(item.id, title: r.edit.title, note: r.edit.note,
                              textContent: r.edit.text_content, language: r.edit.language,
                              at: BridgeDate.next(after: item.updatedAt))
        dirty = true
        return try detail(item)
    }

    private func apply(_ r: BridgeApplyRequest) throws -> BridgeJSON {
        try BridgeDate.validateRevision(r.expected_updated_at)
        let item = try required(r.id)
        guard BridgeDate.string(item.updatedAt) == r.expected_updated_at else { throw BridgeFailure.conflict }
        let date = BridgeDate.next(after: item.updatedAt)
        switch r.command {
        case .archive: try repository.archive(item.id, at: date)
        case .restore_archive: try repository.restoreFromArchive(item.id, at: date)
        case .trash: try repository.trash(item.id, at: date)
        case .restore_trash: try repository.restoreFromTrash(item.id, at: date)
        case .pin: try repository.setPinned(item.id, pinned: true, at: date)
        case .unpin: try repository.setPinned(item.id, pinned: false, at: date)
        }
        dirty = true
        return try detail(item)
    }

    private func rebuild(window: SearchWindow = SearchWindow()) async throws {
        do {
            // Two derived indexes apply pin filtering before SQLite's bounded limit.
            if index == nil { index = try makeIndex(root.url.appendingPathComponent("Search.sqlite")) }
            if pinnedIndex == nil { pinnedIndex = try makeIndex(root.url.appendingPathComponent("PinnedSearch.sqlite")) }
            // SQLite's epoch Double dates can round across exact nanosecond boundaries.
            // Apply the exact native/wire window before indexing and before the query limit.
            let documents = try repository.allItems().filter { window.contains($0.createdAt) }.map(SearchDocument.init(item:))
            try await index!.rebuild(documents)
            try await pinnedIndex!.rebuild(documents.filter(\.isPinned))
            indexedWindow = window
            dirty = false
        } catch {
            dirty = true
            throw BridgeFailure.index
        }
    }

    private func search(_ r: BridgeSearchRequest) async throws -> BridgeJSON {
        guard r.limit == nil || (1...10_000).contains(r.limit!) else { throw BridgeFailure.invalid }
        let window = try SearchWindow(after: r.added_after.map { try BridgeTimestamp($0) },
                                      before: r.added_before.map { try BridgeTimestamp($0) })
        let query = SearchQuery(text: r.text ?? "", type: r.item_type, sourceApp: r.source_app,
                                status: r.status, includeTrashed: r.include_trashed ?? false, limit: r.limit ?? 200)
        if dirty || window != indexedWindow { try await rebuild(window: window) }
        let ids: [UUID]
        do { ids = try await (r.pinned_only == true ? pinnedIndex! : index!).search(query) }
        catch { dirty = true; throw BridgeFailure.index }
        return .array(try ids.compactMap { id in
            guard let item = try repository.item(id: id) else { return nil }
            return summary(item)
        })
    }

    private static func validateURL(_ value: String?) throws {
        let value = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = value.range(of: "://") else { throw BridgeFailure.invalid }
        let rest = value[separator.upperBound...]
        guard !rest.isEmpty, !rest.hasPrefix("/"), !rest.hasPrefix("\\") else { throw BridgeFailure.invalid }
        let bytes = Array(value.utf8)
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:/?#[]@!$&'()*+,;=".utf8)
        let hex = Set("0123456789abcdefABCDEF".utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == 37 {
                guard i + 2 < bytes.count, hex.contains(bytes[i + 1]), hex.contains(bytes[i + 2]) else {
                    throw BridgeFailure.invalid
                }
                i += 3
            } else {
                guard allowed.contains(bytes[i]) else { throw BridgeFailure.invalid }
                i += 1
            }
        }
        guard let c = URLComponents(string: value), let url = c.url,
              ["http", "https"].contains(c.scheme?.lowercased() ?? ""),
              let host = c.host, !host.isEmpty, url.absoluteString == value else { throw BridgeFailure.invalid }
    }

    func summary(_ item: StowItem) -> BridgeJSON {
        .object([
            "id": .string(item.id.uuidString.lowercased()), "item_type": .string(item.type.rawValue),
            "title": .string(item.title), "source_app": .optional(item.sourceApp),
            "created_at": .date(item.createdAt), "updated_at": .date(item.updatedAt),
            "status": .string(item.status.rawValue), "is_pinned": .bool(item.isPinned),
        ])
    }

    func detail(_ item: StowItem, replayed: Bool = false) throws -> BridgeJSON {
        // Do not access external-storage Data fields to construct bridge responses.
        let attachments: [BridgeJSON] = try repository.attachments(itemID: item.id).map {
            .object(["id": .string($0.id.uuidString.lowercased()), "file_name": .string($0.fileName),
                     "content_type": .string($0.contentType), "byte_count": .integer(Int64($0.byteCount))])
        }
        let id = item.id
        let count = try container.mainContext.fetchCount(FetchDescriptor<StowRepresentation>(
            predicate: #Predicate { $0.itemID == id }
        ))
        return .object([
            "capture_replayed": .bool(replayed), "attachments": .array(attachments),
            "representations_count": .integer(Int64(count)), "item": Self.snapshot(item),
        ])
    }

    static func snapshot(_ i: StowItem) -> BridgeJSON {
        .object([
            "id": .string(i.id.uuidString.lowercased()), "capture_id": .string(i.captureID.uuidString.lowercased()),
            "item_type": .string(i.type.rawValue), "title": .string(i.title),
            "text_content": .optional(i.textContent), "url_string": .optional(i.urlString),
            "file_name": .optional(i.fileName), "source_app": .optional(i.sourceApp),
            "source_domain": .optional(i.sourceDomain), "note": .optional(i.note), "language": .optional(i.language),
            "link_description": .optional(i.linkDescription), "favicon_data": .null, "link_preview_image_data": .null,
            "created_at": .date(i.createdAt), "updated_at": .date(i.updatedAt),
            "last_used_at": .date(i.lastUsedAt), "last_captured_at": .date(i.lastCapturedAt),
            "use_count": .integer(Int64(i.useCount)), "content_fingerprint": .optional(i.contentFingerprint),
            "status": .string(i.status.rawValue), "is_pinned": .bool(i.isPinned),
            "trashed_at": .date(i.trashedAt), "status_before_trash": .optional(i.statusBeforeTrash?.rawValue),
        ])
    }
}
