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

public enum CaptureIngestionOutcome {
    case created(StowItem)
    case coalesced(StowItem)

    public var item: StowItem {
        switch self {
        case .created(let item), .coalesced(let item): item
        }
    }
}

@MainActor
public final class StowRepository {
    public let modelContext: ModelContext
    public private(set) var representationFetchCount = 0

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        modelContext.autosaveEnabled = false
    }

    @discardableResult
    public func create(from draft: CaptureDraft, at date: Date = Date()) throws -> StowItem {
        try create(from: draft, attachmentData: nil, representations: [], at: date)
    }

    @discardableResult
    public func create(
        from draft: CaptureDraft,
        representations: [StowRepresentationDraft],
        at date: Date = Date()
    ) throws -> StowItem {
        try create(from: draft, attachmentData: nil, representations: representations, at: date)
    }

    @discardableResult
    public func create(
        from draft: CaptureDraft,
        attachmentData: Data?,
        representations: [StowRepresentationDraft],
        at date: Date = Date()
    ) throws -> StowItem {
        let normalized = try draft.normalized()
        try StowRepresentationValidator.validate(representations)
        if let existing = try allItems().first(where: { $0.captureID == normalized.id }) {
            let existingAttachments = try attachments(itemID: existing.id)
            let existingRepresentations = try representationsWithoutCounting(itemID: existing.id)
            let needsAttachment = attachmentData != nil && existingAttachments.isEmpty
            let needsRepresentations = !representations.isEmpty && existingRepresentations.isEmpty
            guard needsAttachment || needsRepresentations else { return existing }
            if needsAttachment, let attachmentData {
                insertAttachment(data: attachmentData, draft: normalized, itemID: existing.id, at: date)
            }
            if needsRepresentations {
                insertRepresentations(representations, itemID: existing.id, at: date)
            }
            do {
                try modelContext.save()
                return existing
            } catch {
                modelContext.rollback()
                throw error
            }
        }
        let item = StowItem(draft: normalized, createdAt: date)
        modelContext.insert(item)
        if let attachmentData {
            insertAttachment(data: attachmentData, draft: normalized, itemID: item.id, at: date)
        }
        insertRepresentations(representations, itemID: item.id, at: date)
        do {
            try modelContext.save()
            return item
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    public func ingestClipboard(
        _ draft: CaptureDraft,
        attachmentData: Data? = nil,
        representations: [StowRepresentationDraft] = [],
        at date: Date = Date()
    ) throws -> CaptureIngestionOutcome {
        let normalized = try draft.normalized()
        try StowRepresentationValidator.validate(representations)
        if let existing = try allItems().first(where: { $0.captureID == normalized.id }) {
            return .coalesced(existing)
        }
        let fingerprint = try ClipboardContentFingerprint.make(
            draft: normalized,
            attachmentData: attachmentData,
            auxiliaryRepresentations: representations.map {
                ClipboardFingerprintRepresentation(
                    typeIdentifier: $0.typeIdentifier,
                    data: $0.data
                )
            }
        )
        if let existing = try allItems().first(where: {
            $0.status != .trashed && $0.contentFingerprint == fingerprint
        }) {
            existing.lastCapturedAt = date
            existing.sourceApp = normalized.sourceApp
            existing.updatedAt = date
            try modelContext.save()
            return .coalesced(existing)
        }

        let item = StowItem(draft: normalized, createdAt: date)
        item.contentFingerprint = fingerprint
        item.lastCapturedAt = date
        modelContext.insert(item)
        if let attachmentData {
            insertAttachment(data: attachmentData, draft: normalized, itemID: item.id, at: date)
        }
        insertRepresentations(representations, itemID: item.id, at: date)
        do {
            try modelContext.save()
            return .created(item)
        } catch {
            modelContext.rollback()
            throw error
        }
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
        try archive([id], at: date)
    }

    public func archive(_ ids: [UUID], at date: Date = Date()) throws {
        try mutateItems(ids) { $0.archive(at: date) }
    }

    public func restoreFromArchive(_ id: UUID, at date: Date = Date()) throws {
        try restoreFromArchive([id], at: date)
    }

    public func restoreFromArchive(_ ids: [UUID], at date: Date = Date()) throws {
        try mutateItems(ids) { $0.restoreFromArchive(at: date) }
    }

    public func trash(_ id: UUID, at date: Date = Date()) throws {
        try trash([id], at: date)
    }

    public func trash(_ ids: [UUID], at date: Date = Date()) throws {
        try mutateItems(ids) { $0.trash(at: date) }
    }

    public func restoreFromTrash(_ id: UUID, at date: Date = Date()) throws {
        try restoreFromTrash([id], at: date)
    }

    public func restoreFromTrash(_ ids: [UUID], at date: Date = Date()) throws {
        try mutateItems(ids) { $0.restoreFromTrash(at: date) }
    }

    public func setPinned(_ id: UUID, pinned: Bool, at date: Date = Date()) throws {
        try setPinned([id], pinned: pinned, at: date)
    }

    public func setPinned(_ ids: [UUID], pinned: Bool, at date: Date = Date()) throws {
        try mutateItems(ids) { $0.setPinned(pinned, at: date) }
    }

    public func recordSuccessfulUse(_ id: UUID, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        item.recordSuccessfulUse(at: date)
        try modelContext.save()
    }

    public func update(_ id: UUID, title: String, note: String?, textContent: String?, language: String?, at date: Date = Date()) throws {
        let item = try requiredItem(id)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let updatesText = item.type == .text || item.type == .code
        let originalText = textContent ?? ""
        let displayText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased()
        if updatesText, displayText.isEmpty { throw CaptureValidationError.missingText }

        let changesCanonicalContent = updatesText && (
            item.textContent != originalText || item.language != cleanLanguage
        )
        item.title = cleanTitle.isEmpty ? item.title : cleanTitle
        item.note = cleanNote
        if updatesText {
            item.textContent = originalText
            item.language = cleanLanguage
        }
        if changesCanonicalContent {
            for representation in try representations(itemID: item.id) {
                modelContext.delete(representation)
            }
            item.contentFingerprint = try ClipboardContentFingerprint.make(item: item)
        }
        item.updatedAt = date
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
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

    public func allAttachments() throws -> [StowAttachment] {
        try modelContext.fetch(FetchDescriptor<StowAttachment>())
    }

    public func attachments(itemID: UUID) throws -> [StowAttachment] {
        try allAttachments().filter { $0.itemID == itemID }
    }

    public func allRepresentations() throws -> [StowRepresentation] {
        try modelContext.fetch(FetchDescriptor<StowRepresentation>())
    }

    public func representations(itemID: UUID) throws -> [StowRepresentation] {
        representationFetchCount += 1
        return try representationsWithoutCounting(itemID: itemID)
    }

    private func representationsWithoutCounting(itemID: UUID) throws -> [StowRepresentation] {
        try allRepresentations()
            .filter { $0.itemID == itemID }
            .sorted { lhs, rhs in
                if lhs.ordinal == rhs.ordinal { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.ordinal < rhs.ordinal
            }
    }

    @discardableResult
    public func backfillContentFingerprints(limit: Int = 200) throws -> Int {
        let missing = try allItems().filter { $0.contentFingerprint == nil }.prefix(max(0, limit))
        var updated = 0
        for item in missing {
            let attachment = try attachments(itemID: item.id).first
            do {
                let representations = try representations(itemID: item.id)
                item.contentFingerprint = try ClipboardContentFingerprint.make(
                    item: item,
                    attachment: attachment,
                    auxiliaryRepresentations: representations.map {
                        ClipboardFingerprintRepresentation(
                            typeIdentifier: $0.typeIdentifier,
                            data: $0.data
                        )
                    }
                )
                updated += 1
            } catch ClipboardFingerprintError.missingAttachmentData {
                continue
            }
        }
        if updated > 0 { try modelContext.save() }
        return updated
    }

    @discardableResult
    public func purgeExpiredTrash(at date: Date = Date(), retentionDays: Int = 30) throws -> Int {
        let expired = try allItems().filter { $0.shouldPurge(at: date, retentionDays: retentionDays) }
        guard !expired.isEmpty else { return 0 }
        let expiredIDs = Set(expired.map(\.id))
        for attachment in try modelContext.fetch(FetchDescriptor<StowAttachment>()) where expiredIDs.contains(attachment.itemID) {
            modelContext.delete(attachment)
        }
        for representation in try modelContext.fetch(FetchDescriptor<StowRepresentation>()) where expiredIDs.contains(representation.itemID) {
            modelContext.delete(representation)
        }
        for item in expired { modelContext.delete(item) }
        try modelContext.save()
        return expired.count
    }

    private func mutateItems(_ ids: [UUID], mutation: (StowItem) -> Void) throws {
        let uniqueIDs = Array(Set(ids))
        guard !uniqueIDs.isEmpty else { return }
        let requestedIDs = Set(uniqueIDs)
        let matches = try allItems().filter { requestedIDs.contains($0.id) }
        guard matches.count == requestedIDs.count else { throw StowRepositoryError.itemNotFound }
        for item in matches { mutation(item) }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func insertAttachment(
        data: Data,
        draft: CaptureDraft,
        itemID: UUID,
        at date: Date
    ) {
        let imageInfo = AttachmentStore.imageInfo(data)
        modelContext.insert(StowAttachment(
            itemID: itemID,
            data: data,
            thumbnailData: imageInfo.thumbnail,
            contentType: draft.contentType ?? "application/octet-stream",
            fileName: draft.fileName ?? draft.stagedAttachmentName ?? "Attachment",
            pixelWidth: imageInfo.width,
            pixelHeight: imageInfo.height,
            createdAt: date
        ))
    }

    private func insertRepresentations(
        _ representations: [StowRepresentationDraft],
        itemID: UUID,
        at date: Date
    ) {
        for representation in representations {
            modelContext.insert(StowRepresentation(
                itemID: itemID,
                typeIdentifier: representation.typeIdentifier,
                data: representation.data,
                ordinal: representation.ordinal,
                createdAt: date
            ))
        }
    }

    private func requiredItem(_ id: UUID) throws -> StowItem {
        guard let item = try item(id: id) else { throw StowRepositoryError.itemNotFound }
        return item
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
