import Foundation
import SwiftData

public enum StowRepositoryError: Error, Equatable, LocalizedError {
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .itemNotFound: "The item no longer exists."
        }
    }
}

@MainActor
public final class StowRepository {
    public let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        modelContext.autosaveEnabled = false
    }

    @discardableResult
    public func create(from draft: CaptureDraft, at date: Date = Date()) throws -> StowItem {
        let normalized = try draft.normalized()
        if let existing = try allItems().first(where: { $0.captureID == normalized.id }) {
            return existing
        }
        let item = StowItem(draft: normalized, createdAt: date)
        modelContext.insert(item)
        try modelContext.save()
        return item
    }

    public func allItems() throws -> [StowItem] {
        try modelContext.fetch(FetchDescriptor<StowItem>())
    }

    public func item(id: UUID) throws -> StowItem? {
        try allItems().first(where: { $0.id == id })
    }

    public func items(in status: ItemStatus) throws -> [StowItem] {
        try allItems()
            .filter { $0.status == status }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public func recent() throws -> [StowItem] {
        try allItems()
            .filter { $0.status != .trashed && $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    public func pinned() throws -> [StowItem] {
        try allItems()
            .filter { $0.status != .trashed && $0.isPinned }
            .sorted { lhs, rhs in
                if lhs.lastUsedAt != rhs.lastUsedAt { return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast) }
                return lhs.createdAt > rhs.createdAt
            }
    }

    public func archive(_ id: UUID, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        item.archive(at: date)
        try modelContext.save()
    }

    public func restoreFromArchive(_ id: UUID, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        item.restoreFromArchive(at: date)
        try modelContext.save()
    }

    public func trash(_ id: UUID, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        item.trash(at: date)
        try modelContext.save()
    }

    public func restoreFromTrash(_ id: UUID, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        item.restoreFromTrash(at: date)
        try modelContext.save()
    }

    public func setPinned(_ id: UUID, pinned: Bool, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        item.setPinned(pinned, at: date)
        try modelContext.save()
    }

    public func recordSuccessfulUse(_ id: UUID, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        item.recordSuccessfulUse(at: date)
        try modelContext.save()
    }

    public func update(_ id: UUID, title: String, note: String?, textContent: String?, language: String?, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = cleanTitle.isEmpty ? item.title : cleanTitle
        item.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if item.type == .text || item.type == .code {
            let cleanText = textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cleanText.isEmpty else { throw CaptureValidationError.missingText }
            item.textContent = cleanText
            item.language = language?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        }
        item.updatedAt = date
        try modelContext.save()
    }

    public func updateLinkMetadata(_ id: UUID, metadata: LinkMetadata, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        guard item.type == .link else { return }
        if let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
           item.title == item.sourceDomain || item.title.isEmpty {
            item.title = title
        }
        item.linkDescription = metadata.description
        item.sourceDomain = metadata.domain ?? item.sourceDomain
        item.faviconData = metadata.faviconData
        item.linkPreviewImageData = metadata.previewImageData
        item.updatedAt = date
        try modelContext.save()
    }

    public func addAttachment(_ attachment: StowAttachment) throws {
        modelContext.insert(attachment)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(attachment)
            throw error
        }
    }

    public func attachments(itemID: UUID) throws -> [StowAttachment] {
        try modelContext.fetch(FetchDescriptor<StowAttachment>()).filter { $0.itemID == itemID }
    }

    @discardableResult
    public func purgeExpiredTrash(at date: Date = Date(), retentionDays: Int = 30) throws -> Int {
        let expired = try allItems().filter { $0.shouldPurge(at: date, retentionDays: retentionDays) }
        guard !expired.isEmpty else { return 0 }
        let expiredIDs = Set(expired.map(\.id))
        for attachment in try modelContext.fetch(FetchDescriptor<StowAttachment>()) where expiredIDs.contains(attachment.itemID) {
            modelContext.delete(attachment)
        }
        for item in expired { modelContext.delete(item) }
        try modelContext.save()
        return expired.count
    }

    private func requiredItem(_ id: UUID) throws -> StowItem {
        guard let item = try item(id: id) else { throw StowRepositoryError.itemNotFound }
        return item
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
