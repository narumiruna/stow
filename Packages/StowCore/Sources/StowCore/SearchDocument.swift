import Foundation

public struct SearchDocument: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let content: String
    public let type: ItemType
    public let sourceApp: String?
    public let createdAt: Date
    public let status: ItemStatus
    public let isPinned: Bool
    public let lastUsedAt: Date?

    public init(
        id: UUID,
        content: String,
        type: ItemType,
        sourceApp: String?,
        createdAt: Date,
        status: ItemStatus,
        isPinned: Bool,
        lastUsedAt: Date?
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.status = status
        self.isPinned = isPinned
        self.lastUsedAt = lastUsedAt
    }

    public init(item: StowItem) {
        id = item.id
        content = [
            item.title,
            item.urlString,
            item.sourceDomain,
            item.textContent,
            item.note,
            item.fileName,
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        type = item.type
        sourceApp = item.sourceApp
        createdAt = item.createdAt
        status = item.status
        isPinned = item.isPinned
        lastUsedAt = item.lastUsedAt
    }
}
