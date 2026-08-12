import Foundation
import SwiftData

public enum ItemType: String, Codable, CaseIterable, Identifiable, Sendable {
    case link
    case text
    case code
    case image
    case file

    public var id: String { rawValue }
}

public enum ItemStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inbox
    case archived
    case trashed

    public var id: String { rawValue }
}

extension StowSchemaV1 {
    @Model
    public final class StowItem {
        public var id: UUID = UUID()
        public var captureID: UUID = UUID()
        public var type: ItemType = ItemType.text
        public var title: String = ""
        public var textContent: String?
        public var urlString: String?
        public var fileName: String?
        public var sourceApp: String?
        public var sourceDomain: String?
        public var note: String?
        public var language: String?
        public var linkDescription: String?
        @Attribute(.externalStorage) public var faviconData: Data?
        @Attribute(.externalStorage) public var linkPreviewImageData: Data?
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var lastUsedAt: Date?
        public var useCount: Int = 0
        public var status: ItemStatus = ItemStatus.inbox
        public var isPinned: Bool = false
        public var trashedAt: Date?
        public var statusBeforeTrash: ItemStatus?

        public init(
            id: UUID = UUID(),
            captureID: UUID? = nil,
            type: ItemType,
            title: String,
            textContent: String? = nil,
            urlString: String? = nil,
            fileName: String? = nil,
            sourceApp: String? = nil,
            sourceDomain: String? = nil,
            note: String? = nil,
            language: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date? = nil,
            lastUsedAt: Date? = nil,
            useCount: Int = 0,
            status: ItemStatus = .inbox,
            isPinned: Bool = false,
            trashedAt: Date? = nil,
            statusBeforeTrash: ItemStatus? = nil
        ) {
            self.id = id
            self.captureID = captureID ?? id
            self.type = type
            self.title = title
            self.textContent = textContent
            self.urlString = urlString
            self.fileName = fileName
            self.sourceApp = sourceApp
            self.sourceDomain = sourceDomain
            self.note = note
            self.language = language
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.lastUsedAt = lastUsedAt
            self.useCount = useCount
            self.status = status
            self.isPinned = isPinned
            self.trashedAt = trashedAt
            self.statusBeforeTrash = statusBeforeTrash
        }
    }
}

extension StowSchemaV2 {
    @Model
    public final class StowItem {
        public var id: UUID = UUID()
        public var captureID: UUID = UUID()
        public var type: ItemType = ItemType.text

        public var title: String = ""
        public var textContent: String?
        public var urlString: String?
        public var fileName: String?
        public var sourceApp: String?
        public var sourceDomain: String?
        public var note: String?
        public var language: String?
        public var linkDescription: String?
        @Attribute(.externalStorage) public var faviconData: Data?
        @Attribute(.externalStorage) public var linkPreviewImageData: Data?

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var lastUsedAt: Date?
        public var lastCapturedAt: Date?
        public var useCount: Int = 0
        public var contentFingerprint: String?

        public var status: ItemStatus = ItemStatus.inbox
        public var isPinned: Bool = false
        public var trashedAt: Date?
        public var statusBeforeTrash: ItemStatus?

        public init(
            id: UUID = UUID(),
            captureID: UUID? = nil,
            type: ItemType,
            title: String,
            textContent: String? = nil,
            urlString: String? = nil,
            fileName: String? = nil,
            sourceApp: String? = nil,
            sourceDomain: String? = nil,
            note: String? = nil,
            language: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date? = nil,
            lastUsedAt: Date? = nil,
            lastCapturedAt: Date? = nil,
            useCount: Int = 0,
            contentFingerprint: String? = nil,
            status: ItemStatus = .inbox,
            isPinned: Bool = false,
            trashedAt: Date? = nil,
            statusBeforeTrash: ItemStatus? = nil
        ) {
            self.id = id
            self.captureID = captureID ?? id
            self.type = type
            self.title = title
            self.textContent = textContent
            self.urlString = urlString
            self.fileName = fileName
            self.sourceApp = sourceApp
            self.sourceDomain = sourceDomain
            self.note = note
            self.language = language
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.lastUsedAt = lastUsedAt
            self.lastCapturedAt = lastCapturedAt
            self.useCount = useCount
            self.contentFingerprint = contentFingerprint
            self.status = status
            self.isPinned = isPinned
            self.trashedAt = trashedAt
            self.statusBeforeTrash = statusBeforeTrash
        }

        public convenience init(draft: CaptureDraft, createdAt: Date = Date()) {
            self.init(
                captureID: draft.id,
                type: draft.type,
                title: draft.title,
                textContent: draft.textContent,
                urlString: draft.urlString,
                fileName: draft.fileName,
                sourceApp: draft.sourceApp,
                sourceDomain: draft.sourceDomain,
                note: draft.note,
                language: draft.language,
                createdAt: createdAt,
                status: draft.directlyArchive ? .archived : .inbox,
                isPinned: draft.isPinned
            )
        }

        public func archive(at date: Date = Date()) {
            guard status != .trashed else { return }
            status = .archived
            updatedAt = date
        }

        public func restoreFromArchive(at date: Date = Date()) {
            guard status == .archived else { return }
            status = .inbox
            updatedAt = date
        }

        public func trash(at date: Date = Date()) {
            guard status != .trashed else { return }
            statusBeforeTrash = status
            status = .trashed
            trashedAt = date
            updatedAt = date
        }

        public func restoreFromTrash(at date: Date = Date()) {
            guard status == .trashed else { return }
            let restoredStatus = statusBeforeTrash == .archived ? ItemStatus.archived : ItemStatus.inbox
            status = restoredStatus
            statusBeforeTrash = nil
            trashedAt = nil
            updatedAt = date
        }

        public func setPinned(_ pinned: Bool, at date: Date = Date()) {
            guard isPinned != pinned else { return }
            isPinned = pinned
            updatedAt = date
        }

        public func recordSuccessfulUse(at date: Date = Date()) {
            useCount += 1
            lastUsedAt = date
            updatedAt = date
        }

        public func shouldPurge(at date: Date = Date(), retentionDays: Int = 30) -> Bool {
            guard status == .trashed, let trashedAt else { return false }
            return date >= trashedAt.addingTimeInterval(TimeInterval(retentionDays) * 86_400)
        }
    }
}

public typealias StowItem = StowSchemaV2.StowItem
